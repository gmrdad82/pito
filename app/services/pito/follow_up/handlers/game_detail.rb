# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for game-detail events (reply_target: "game_detail").
      #
      # The detail message is stamped `reply_target: "game_detail"` by
      # `Pito::Game::DetailMessage.call`. The user can reply:
      #
      #   #<handle> rm / delete
      #     → Emit a confirmation event (`command: "game_delete"`) using the
      #       existing executor branch that already destroys the Game row.
      #       Mode: :append — the confirmation lands as a new event below the card.
      #
      #   #<handle> resync
      #     → Emit a confirmation event (`command: "game_resync"`) whose executor
      #       branch enqueues `GameIgdbSync`. The card stays follow-up-able.
      #
      #   #<handle> link to video <id|title>
      #     → Resolve the video (id `#N`/`N` or title ILIKE),
      #       `VideoGameLink.find_or_create_by!`, append a witty ack.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Game` for the model.
      class GameDetail < Pito::FollowUp::Handler
        self.target "game_detail"
        self.mode   :append
        self.actions "rm", "resync", "link"

        # @param event        [Event]        the game-detail event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:)
          action, args = parse_rest(rest)

          case action
          when "rm", "delete"
            handle_delete(event, conversation)
          when "resync"
            handle_resync(event, conversation)
          when "link"
            handle_link(event, args, conversation)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # ── rm / delete ────────────────────────────────────────────────────────

        def handle_delete(event, conversation)
          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          payload = Pito::MessageBuilder::Game::DeleteConfirmation.call(game, conversation:)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "confirmation", payload: payload } ]
          )
        end

        # ── resync ─────────────────────────────────────────────────────────────

        def handle_resync(event, conversation)
          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          payload = Pito::MessageBuilder::Game::ResyncConfirmation.call(game, conversation:)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "confirmation", payload: payload } ]
          )
        end

        # ── link to video <id|title> ───────────────────────────────────────────

        def handle_link(event, args, conversation)
          # Drop the word "to" and "video"/"videos"
          words = args.to_s.strip.split
          words = words.drop(1) if words.first&.downcase == "to"
          words = words.drop(1) if %w[video videos].include?(words.first&.downcase)
          ref   = words.join(" ").strip

          if ref.blank?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.missing_video_ref",
              message_args: {}
            )
          end

          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          video = resolve_video(ref)
          if video.nil?
            return Pito::FollowUp::Result::Append.new(
              events: [
                {
                  kind:    "system",
                  payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref)
                }
              ]
            )
          end

          VideoGameLink.find_or_create_by!(video: video, game: game)

          text = Pito::Copy.render("pito.copy.games.linked", { game: game.title, video: video.title })
          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "system", payload: Pito::MessageBuilder::Text.call(text) } ]
          )
        end

        # ── helpers ────────────────────────────────────────────────────────────

        # Resolve the game from the event payload.
        # DetailMessage stamps `game_id` into the payload (added in P12).
        def resolve_game_from_event(event)
          payload = event.payload.with_indifferent_access
          game_id = payload[:game_id]
          return nil unless game_id.present?

          ::Game.find_by(id: game_id)
        end

        def resolve_video(ref)
          id = ref.delete_prefix("#")
          if id.match?(/\A\d+\z/)
            ::Video.find_by(id: id)
          else
            ::Video.find_by("title ILIKE ?", ref)
          end
        end

        def game_not_found_error
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.game_enhanced.errors.game_not_found",
            message_args: {}
          )
        end
      end
    end
  end
end
