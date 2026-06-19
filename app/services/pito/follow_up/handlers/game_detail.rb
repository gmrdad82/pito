# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for game-detail events (reply_target: "game_detail").
      #
      # The detail message is stamped `reply_target: "game_detail"` by
      # `Pito::MessageBuilder::Game::Detail.call`. The user can reply:
      #
      #   #<handle> rm / delete
      #     → Delegated to Chat::Handlers::Delete via VerbDelegator.
      #
      #   #<handle> reindex
      #     → Delegated to Chat::Handlers::Reindex via VerbDelegator. The
      #       follow-up context provides the game_id so Reindex resolves the
      #       game without a ref. Emits a Voyage re-embed confirmation.
      #
      #   #<handle> link [to] [video] <id|title>
      #     → Delegated to Chat::Handlers::Link via VerbDelegator. The handler
      #       reads game_id from the source event and the video ref from rest.
      #
      #   #<handle> footage [update] <hours>
      #     → Set this game's total footage hours (ceil'd UP to the next 0.5),
      #       mirroring the `footage update <id> <hours>` chat verb (the id is
      #       implied by the card). Reachable via shift+r, which seeds `#<handle> `.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Game` for the model.
      class GameDetail < Pito::FollowUp::Handler
        self.target "game_detail"
        self.mode   :append
        self.actions "rm", "delete", "reindex", "link", "unlink", "footage", "platform"

        # @param event        [Event]        the game-detail event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:)
          action, args = parse_rest(rest)

          if %w[rm delete reindex link unlink platform].include?(action)
            return Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:)
          end

          case action
          when "footage"
            handle_footage(event, args, conversation)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # ── footage [update] <hours> ──────────────────────────────────────────────

        # `#<handle> footage [update] <hours>` — the game is known from the segment,
        # so the tail is the new total footage in hours, ceil'd UP to the next 0.5
        # (BigDecimal-exact). Sets `footage_hours`, same as the `footage update
        # <id> <hours>` chat verb (id implied by the card).
        def handle_footage(event, args, conversation)
          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          hours = parse_footage_hours(args)
          if hours.nil?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.missing_hours",
              message_args: {}
            )
          end

          game.update!(footage_hours: hours)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: :system, payload: Pito::MessageBuilder::Text.call(
              "pito.copy.footage.updated",
              game:  game.title,
              hours: Pito::Formatter::FootageHours.call(game.footage_hours)
            ) } ]
          )
        end

        # Parse the `footage` args tail into footage hours, ceil'd UP to the next
        # 0.5 (1800 s = 0.5 h). Tolerates an optional leading `update` token so both
        # `footage <hours>` and `footage update <hours>` work. Non-numeric/negative
        # → nil (usage hint). BigDecimal keeps the 0.5 step exact.
        def parse_footage_hours(args)
          text  = args.to_s.strip.sub(/\Aupdate\b\s*/i, "").strip
          value = BigDecimal(text)
          return nil if value.negative?

          (value * 2).ceil / 2r
        rescue ArgumentError, TypeError
          nil
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

        def game_not_found_error
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.game_detail.errors.game_not_found",
            message_args: {}
          )
        end
      end
    end
  end
end
