# frozen_string_literal: true

# Handler for `link game <ref> to video <ref>` / `link video <ref> to game <ref>`.
#
# Free-chat: drop noun fillers from the raw body text, then split on the word
# ` to ` (case-insensitive) into a left and right half. Each half begins with a
# noun discriminator (`game`/`games` or `video`/`videos`) followed by a ref
# (id `#N`/`N` or title ILIKE).
#
# Follow-up: ONE side is the source card's entity (read from the payload);
# the OTHER side is parsed from `follow_up.rest` — drop a leading `to`, drop a
# leading noun filler, the remainder is the ref.
#
# Resolution:
#   - game  → id → `::Game.find_by(id:)`; else `::Game.find_by("title ILIKE ?")`
#   - video → id → `::Video.find_by(id:)`; else `::Video.find_by("title ILIKE ?")`
#
# `VideoGameLink.find_or_create_by!` makes linking idempotent.
# The model's `after_commit` already enqueues game-stats refresh — not duplicated.
module Pito
  module Chat
    module Handlers
      class Link < Pito::Chat::Handler
        self.verb = :link
        self.description_key = "pito.chat.link.descriptions.link"

        GAME_NOUNS  = %w[game games].freeze
        VIDEO_NOUNS = %w[video videos].freeze

        def call
          return follow_up_link if follow_up?

          raw = message.body_tokens.map(&:value).join(" ")
          parts = raw.split(/\bto\b/i, 2)

          return usage_hint if parts.size < 2

          left_words  = parts[0].strip.split
          right_words = parts[1].strip.split

          return usage_hint if left_words.empty? || right_words.empty?

          game, video = resolve_sides(left_words, right_words)
          return game  if game.is_a?(Pito::Chat::Result::Ok)  # not-found or usage
          return video if video.is_a?(Pito::Chat::Result::Ok)

          create_link(game, video)
        end

        private

        # ── Follow-up branch ───────────────────────────────────────────────────

        # ONE side comes from the source card's payload; the OTHER from follow_up.rest.
        # `video_target?` delegates to reply_target, so video_detail → video branch.
        def follow_up_link
          if video_target?(VIDEO_NOUNS)
            video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUNS)
            return not_found_video("") if video.nil?

            game = resolve_other_side(::Game, GAME_NOUNS)
            return game if result?(game)

            create_link(game, video)
          else
            game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUNS)
            return not_found_game("") if game.nil?

            video = resolve_other_side(::Video, VIDEO_NOUNS)
            return video if result?(video)

            create_link(game, video)
          end
        end

        # Parse the other side from follow_up.rest: drop a leading "to", drop a
        # leading noun filler (game/games/video/videos), the remainder is the ref.
        # Returns a record on success; a Result::Ok (not-found) on nil; a
        # Result::Error (usage hint) when the ref is blank.
        def resolve_other_side(entity_class, nouns)
          words = follow_up.rest.to_s.strip.split
          words = words.drop(1) if words.first&.downcase == "to"
          words = words.drop(1) if nouns.include?(words.first&.downcase)
          ref   = words.join(" ").strip

          return usage_hint if ref.blank?

          id     = ref.delete_prefix("#")
          record = if id.match?(/\A\d+\z/)
                     entity_class.find_by(id: id)
          else
                     entity_class.find_by("title ILIKE ?", ref)
          end

          return not_found_game(ref)  if record.nil? && entity_class == ::Game
          return not_found_video(ref) if record.nil? && entity_class == ::Video

          record
        end

        # ── Free-chat helpers ──────────────────────────────────────────────────

        # Returns [game_record, video_record] or one of the two is a Result::Ok
        # (not-found) / Result::Error (usage hint).
        def resolve_sides(left_words, right_words)
          left_noun  = left_words.first.downcase
          right_noun = right_words.first.downcase

          if GAME_NOUNS.include?(left_noun) && VIDEO_NOUNS.include?(right_noun)
            game  = resolve_game(left_words.drop(1))
            video = resolve_video(right_words.drop(1))
          elsif VIDEO_NOUNS.include?(left_noun) && GAME_NOUNS.include?(right_noun)
            video = resolve_video(left_words.drop(1))
            game  = resolve_game(right_words.drop(1))
          else
            return [ usage_hint, nil ]
          end

          [ game, video ]
        end

        def resolve_game(ref_words)
          ref = ref_words.join(" ").strip
          return not_found_game(ref) if ref.blank?

          id = ref.delete_prefix("#")
          record = if id.match?(/\A\d+\z/)
                     ::Game.find_by(id: id)
          else
                     ::Game.find_by("title ILIKE ?", ref)
          end

          record || not_found_game(ref)
        end

        def resolve_video(ref_words)
          ref = ref_words.join(" ").strip
          return not_found_video(ref) if ref.blank?

          id = ref.delete_prefix("#")
          record = if id.match?(/\A\d+\z/)
                     ::Video.find_by(id: id)
          else
                     ::Video.find_by("title ILIKE ?", ref)
          end

          record || not_found_video(ref)
        end

        # ── Shared helpers ─────────────────────────────────────────────────────

        def create_link(game, video)
          VideoGameLink.find_or_create_by!(video: video, game: game)

          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.linked", game: game.title, video: video.title) }
          ])
        end

        def not_found_game(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end

        def not_found_video(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end

        def usage_hint
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.link.usage",
            message_args: {}
          )
        end

        # True when the value is a Chat::Result (Ok or Error) rather than a record.
        # Used to short-circuit after resolve_other_side.
        def result?(value)
          value.is_a?(Pito::Chat::Result::Ok) || value.is_a?(Pito::Chat::Result::Error)
        end
      end
    end
  end
end
