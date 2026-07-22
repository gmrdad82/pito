# frozen_string_literal: true

# Suggests LIBRARY games a freshly-imported, still-unlinked video probably
# belongs to — a nudge for the operator, never an auto-link. Video/game links
# stay explicit (`link`/`unlink`, see `Pito::Chat::Handlers::Link`); this
# class only proposes candidates for the human to confirm.
#
# `link_suggested_at` is the once-only marker: the CALLER stamps it after
# consuming a suggestion (or a no-op run) so a video is only ever offered
# once. This class is read-only on that column — it never writes it.
#
# ── Scoring pipeline ────────────────────────────────────────────────────
#   0. A hard PRECISION GATE runs before any ranking: a game only becomes a
#      candidate at all when at least one of its names (title +
#      `alternative_names`) appears COMPLETE — its full token sequence, as
#      one contiguous order-preserving run — in the title zone (the
#      noise-stripped title) or the description zone (see
#      `qualifying_games`). This blocks a common single word (e.g. a game
#      literally named "Dispatch") from being read out of ordinary prose:
#      "Playing Dispatch today" qualifies, "i dispatch my enemies" doesn't —
#      a SINGLE-token name only qualifies via the description as a
#      case-sensitive whole word spelled exactly as the library entry
#      (`qualifies_via_description?`). Multi-token names, and every
#      single-token name checked against the title zone, stay
#      case-insensitive. A game that fails the gate never reaches scoring,
#      however much partial token overlap it might otherwise share with a
#      zone — that is what makes "Mortal Shell" text stay silent against a
#      library-only "Mortal Shell II".
#   1. Strip the title down to a "candidate zone": lowercase, drop
#      `[bracketed]`/`(parenthesized)` chunks, then optionally cut at the
#      first `:`/`—`/`|` separator and keep only the lead segment — but
#      ONLY when that lead segment actually overlaps a library game (see
#      `candidate_scores`). An ordinary title like "Top 10 Facts: You Won't
#      Believe" has no game in its lead, so the separator is left alone and
#      the whole title stays in play.
#   2. Tokenize the zone and every library game's name (title +
#      `alternative_names`), then score each game by the longest
#      contiguous token run shared with the zone (`Pito::TitleMatch`,
#      extracted here so `Pito::TitleResolve`'s title-resolution ladder
#      reuses the exact same DP instead of reimplementing it). A run
#      anchored at the very start of the zone (the game name IS the lead of
#      the title) outranks a same-length run found mid-title — that is the
#      "exact/prefix full-name matches rank first" rule. A game gated in
#      purely via its description (zero title-zone overlap) is scored the
#      same way against the description's tokens instead, so it still
#      earns a real rank rather than falling out as unscored.
#   3. The numeral rule falls out of run-length scoring rather than being a
#      separate branch: "Mortal Kombat 2: Was it really that good?" scores
#      "Mortal Kombat 2" with a 3-token anchored run and "Mortal Kombat"
#      with only a 2-token anchored run, so the numbered title wins
#      outright (not a tie — no embedding tiebreak needed). When no
#      numbered game exists in the library, the trailing digit simply
#      finds no token to match and is dropped as vid-sequence noise, e.g.
#      "Hades 2" still anchors onto a library-only "Hades".
#   4. Embedding cosine similarity is a TIEBREAK ONLY, used solely to order
#      games that end up with the exact same top score. It is skipped
#      silently (K2) whenever the embedder is unconfigured or the forgiving
#      `Pito::Embedding::Client#embed` call comes back nil — a sidecar
#      hiccup degrades ordering, never raises.
#
# Library-only scope: this class ranks games already present locally. It
# never queries IGDB, so "Hades 2" with only "Hades" linked in this channel's
# library suggests "Hades" even if Hades II legitimately exists on IGDB —
# that gap is closed by importing the game, not by this suggester.
class Video
  class GameLinkSuggester
    MAX_SUGGESTIONS = 5
    SEPARATOR_PATTERN = /[:—|]/

    def self.call(video)
      new(video).call
    end

    def initialize(video)
      @video = video
    end

    def call
      return [] if @video.video_game_links.exists?
      return [] if @video.link_suggested_at.present?

      stripped = strip_noise(@video.title)
      return [] if stripped.blank?

      title_tokens = tokenize(stripped)
      # `strip_noise` was built for titles, but its downcase + bracket/paren
      # stripping is an apt minimal normalization for a description too —
      # both carry the same kind of `[timestamp]`/`(credits)` noise.
      # Reused as-is rather than duplicating a description-specific
      # stripper. Tokenized once here and threaded through gating + scoring
      # (descriptions can be long — never re-tokenize per game).
      description_tokens = tokenize(strip_noise(@video.description))

      qualifying = qualifying_games(title_tokens, description_tokens, @video.description)
      return [] if qualifying.empty?

      zone, scored = candidate_scores(stripped, description_tokens, qualifying)
      return [] if scored.empty?

      top_games(scored, zone)
    end

    private

    # The precision gate (pipeline step 0, see class docstring): only games
    # with a COMPLETE name in the title zone or the description zone survive
    # to be scored at all.
    def qualifying_games(title_tokens, description_tokens, raw_description)
      library.select do |game|
        names(game).any? { |name| qualifies?(name, title_tokens, description_tokens, raw_description) }
      end
    end

    def names(game)
      [ game.title, *Array(game.alternative_names) ].compact
    end

    def qualifies?(name, title_tokens, description_tokens, raw_description)
      return true if Pito::TitleMatch.contains_name?(title_tokens, name)

      qualifies_via_description?(name, description_tokens, raw_description)
    end

    # Multi-token names qualify via the description the same way as the
    # title zone: a complete, contiguous, case-insensitive run. A
    # SINGLE-token name is the false-positive risk (a common word doubling
    # as a verb/noun in prose — a game named "Dispatch" vs. "i dispatch my
    # enemies") so it only qualifies via the description as a
    # case-sensitive whole word spelled EXACTLY as the library entry,
    # matched against the RAW (un-downcased, un-tokenized) description
    # text with word boundaries.
    def qualifies_via_description?(name, description_tokens, raw_description)
      return false if raw_description.blank?

      if Pito::TitleMatch.tokenize(name).size == 1
        raw_description.match?(/\b#{Regexp.escape(name)}\b/)
      else
        Pito::TitleMatch.contains_name?(description_tokens, name)
      end
    end

    # Tries the lead segment (text before the first `:`/`—`/`|`) first, and
    # only falls back to the full stripped title when the lead scores no
    # overlap at all — i.e. the separator wasn't actually splitting a game
    # name off a subtitle. `description_tokens` rides along unchanged
    # either way (the description zone doesn't participate in the
    # lead/full-title split).
    def candidate_scores(stripped, description_tokens, games)
      lead = lead_segment(stripped)
      if lead
        lead_scored = score_games(tokenize(lead), description_tokens, games)
        return [ lead, lead_scored ] if lead_scored.any?
      end

      [ stripped, score_games(tokenize(stripped), description_tokens, games) ]
    end

    def lead_segment(stripped)
      idx = stripped =~ SEPARATOR_PATTERN
      return nil if idx.nil?

      stripped[0...idx].strip.presence
    end

    def strip_noise(title)
      title.to_s.downcase
           .gsub(/\[[^\]]*\]/, " ")
           .gsub(/\([^)]*\)/, " ")
           .squeeze(" ")
           .strip
    end

    def tokenize(text)
      Pito::TitleMatch.tokenize(text)
    end

    # Hash{Game => [anchor_flag, run_length]}, one entry per (already-gated)
    # game that shares at least one contiguous token run with either zone.
    # A game with zero overlap in both zones is left out entirely (never
    # scored 0) — that is what lets an all-miss board return [].
    def score_games(zone_tokens, description_tokens, games)
      return {} if zone_tokens.empty? && description_tokens.empty?

      games.each_with_object({}) do |game, scores|
        score = score_game(game, zone_tokens, description_tokens)
        scores[game] = score if score
      end
    end

    # Best score across the game's title + alternative_names, across BOTH
    # zones (title zone tokens and description tokens) — via the shared
    # `Pito::TitleMatch` scorer (see its docstring for the DP + the
    # "anchored beats longer non-anchored" rank-first rule). Scoring both
    # zones mirrors the gate's two-zone shape, so a game gated in purely by
    # its description still earns a real score instead of dropping out
    # unscored.
    def score_game(game, zone_tokens, description_tokens)
      candidate_names = names(game)
      [
        Pito::TitleMatch.score_names(zone_tokens, candidate_names),
        Pito::TitleMatch.score_names(description_tokens, candidate_names)
      ].compact.max
    end

    # Library-only: never IGDB, see the class comment. Stable `title` order
    # keeps the pre-embedding fallback ordering deterministic.
    def library
      Game.select(:id, :title, :alternative_names, Game::EMBEDDING_COLUMN).order(:title)
    end

    # Only the games sharing the single best score survive — a unique top
    # scorer comes back alone (min 1), a genuine tie is embedding-ranked
    # and capped at MAX_SUGGESTIONS.
    def top_games(scored, zone)
      top_score = scored.values.max
      top = scored.select { |_, score| score == top_score }.keys
      return top.first(1) if top.one?

      (embedding_rank(top, zone) || top).first(MAX_SUGGESTIONS)
    end

    # Cosine-ranks tied games by similarity of the candidate zone's
    # embedding to each game's embedding vector (via the `Game::EMBEDDING_COLUMN`
    # seam / `#embedding_vector`). Returns nil (no reordering) whenever the
    # embedder is unconfigured or the forgiving `embed` call yields nothing —
    # the tie then just keeps title order.
    def embedding_rank(games, zone)
      vector = Pito::Embedding::Client.new.embed([ zone ]).first
      return nil if vector.blank?

      with_embedding, without_embedding = games.partition { |game| game.embedding_vector.present? }
      with_embedding.sort_by { |game| -cosine_similarity(vector, game.embedding_vector) } + without_embedding
    end

    def cosine_similarity(a, b)
      magnitude_a = Math.sqrt(a.sum { |x| x * x })
      magnitude_b = Math.sqrt(b.sum { |x| x * x })
      return 0.0 if magnitude_a.zero? || magnitude_b.zero?

      dot_product = a.zip(b).sum { |x, y| x * y }
      dot_product / (magnitude_a * magnitude_b)
    end
  end
end
