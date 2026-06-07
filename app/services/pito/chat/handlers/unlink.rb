# frozen_string_literal: true

# Handler for `unlink game <ref> from video <ref>` /
# `unlink video <ref> from game <ref>`.
#
# Same parsing as `Link` but splits on ` to ` **or** ` from ` (case-insensitive)
# so users can write either form naturally. Destroys the `VideoGameLink` join
# if present; missing link → gentle "already not linked" message (idempotent).
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
          raw = message.body_tokens.map(&:value).join(" ")
          parts = raw.split(/\b(?:to|from)\b/i, 2)

          return usage_hint if parts.size < 2

          left_words  = parts[0].strip.split
          right_words = parts[1].strip.split

          return usage_hint if left_words.empty? || right_words.empty?

          game, video = resolve_sides(left_words, right_words)
          return game  if game.is_a?(Pito::Chat::Result::Ok)
          return video if video.is_a?(Pito::Chat::Result::Ok)

          link = VideoGameLink.find_by(video: video, game: game)

          if link
            link.destroy!
            text = Pito::Copy.render("pito.copy.games.unlinked", { game: game.title, video: video.title })
          else
            text = "#{game.title} and #{video.title} are already not linked."
          end

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: Pito::MessageBuilder::Text.call(text) } ])
        end

        private

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
            message_key:  "pito.chat.unlink.usage",
            message_args: {}
          )
        end
      end
    end
  end
end
