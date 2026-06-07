# frozen_string_literal: true

# Handler for `link game <ref> to video <ref>` / `link video <ref> to game <ref>`.
#
# Pragmatic parse: drop noun fillers from the raw body text, then split on the
# word ` to ` (case-insensitive) into a left and right half.  Each half begins
# with a noun discriminator (`game`/`games` or `video`/`videos`) followed by a
# ref (id `#N`/`N` or title ILIKE).
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
          raw = message.body_tokens.map(&:value).join(" ")
          parts = raw.split(/\bto\b/i, 2)

          return usage_hint if parts.size < 2

          left_words  = parts[0].strip.split
          right_words = parts[1].strip.split

          return usage_hint if left_words.empty? || right_words.empty?

          game, video = resolve_sides(left_words, right_words)
          return game  if game.is_a?(Pito::Chat::Result::Ok)  # not-found or usage
          return video if video.is_a?(Pito::Chat::Result::Ok)

          VideoGameLink.find_or_create_by!(video: video, game: game)

          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.linked", game: game.title, video: video.title) }
          ])
        end

        private

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
      end
    end
  end
end
