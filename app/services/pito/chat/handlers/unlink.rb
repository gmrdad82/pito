# frozen_string_literal: true

# Handler for `unlink game <id> from video <id>` /
# `unlink video <id> from game <id>`.
#
# Free-chat: split on ` from ` (case-insensitive) into a left and right half.
# Each half begins with a noun discriminator (`game`/`games` or `video`/`videos`)
# followed by a numeric id (plain or with a leading `#`). Title refs are not
# supported — only local numeric ids. Connector word = `from`.
#
# Follow-up: ONE side is the source card's entity (read from the payload);
# the OTHER side is parsed from `follow_up.rest` — drop a leading `to` or
# `from`, drop a leading noun filler, the remainder is the numeric id.
#
# Destroys the `VideoGameLink` join if present; missing link → gentle
# "already not linked" message (idempotent).
# The model's `after_commit` already enqueues game-stats refresh — not duplicated.
module Pito
  module Chat
    module Handlers
      class Unlink < Pito::Chat::Handler
        self.verb = :unlink
        self.description_key = "pito.chat.unlink.descriptions.unlink"

        GAME_NOUNS  = %w[game games].freeze
        VIDEO_NOUNS = %w[video videos].freeze

        def call
          return follow_up_unlink if follow_up?

          raw = message.body_tokens.map(&:value).join(" ")
          parts = raw.split(/\bfrom\b/i, 2)

          return usage_hint if parts.size < 2

          left_words  = parts[0].strip.split
          right_words = parts[1].strip.split

          return usage_hint if left_words.empty? || right_words.empty?

          game, video = resolve_sides(left_words, right_words)
          return game  if result?(game)
          return video if result?(video)

          destroy_link(game, video)
        end

        private

        # ── Follow-up branch ───────────────────────────────────────────────────

        # ONE side comes from the source card's payload; the OTHER from follow_up.rest.
        # `video_target?` delegates to reply_target, so video_detail → video branch.
        def follow_up_unlink
          if video_target?(VIDEO_NOUNS)
            video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUNS)
            return not_found_video("") if video.nil?

            game = resolve_other_side(::Game, GAME_NOUNS)
            return game if result?(game)

            destroy_link(game, video)
          else
            game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUNS)
            return not_found_game("") if game.nil?

            video = resolve_other_side(::Video, VIDEO_NOUNS)
            return video if result?(video)

            destroy_link(game, video)
          end
        end

        # Parse the other side from follow_up.rest: drop a leading "to" or "from",
        # drop a leading noun filler (game/games/video/videos), the remainder is the id.
        # Returns a record on success; a Result::Ok (not-found) when the id isn't
        # found; a Result::Error (usage hint) when the ref is blank or non-numeric.
        def resolve_other_side(entity_class, nouns)
          words = follow_up.rest.to_s.strip.split
          words = words.drop(1) if %w[to from].include?(words.first&.downcase)
          words = words.drop(1) if nouns.include?(words.first&.downcase)
          ref   = words.join(" ").strip

          return usage_hint if ref.blank?

          id = ref.delete_prefix("#")
          return usage_hint unless id.match?(/\A\d+\z/)

          record = entity_class.find_by(id: id)

          return not_found_game(ref)  if record.nil? && entity_class == ::Game
          return not_found_video(ref) if record.nil? && entity_class == ::Video

          record
        end

        # ── Free-chat helpers ──────────────────────────────────────────────────

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
          return usage_hint if ref.blank?

          id = ref.delete_prefix("#")
          return usage_hint unless id.match?(/\A\d+\z/)

          ::Game.find_by(id: id) || not_found_game(ref)
        end

        def resolve_video(ref_words)
          ref = ref_words.join(" ").strip
          return usage_hint if ref.blank?

          id = ref.delete_prefix("#")
          return usage_hint unless id.match?(/\A\d+\z/)

          ::Video.find_by(id: id) || not_found_video(ref)
        end

        # ── Shared helpers ─────────────────────────────────────────────────────

        def destroy_link(game, video)
          link = VideoGameLink.find_by(video: video, game: game)

          if link
            link.destroy!
            Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.unlinked", game: game.title, video: video.title) }
            ])
          else
            Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_linked", game: game.title, video: video.title) }
            ])
          end
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
            message_key:  "pito.chat.unlink.usage",
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
