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
      #   #<handle> footage <path>
      #     → Append the copyable `pito:tools:probe` snippet for this game +
      #       footage folder (shared FootageImport builder with the `footage`
      #       chat verb). Reachable via shift+r, which seeds `#<handle> `.
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

        # ── footage <path> ────────────────────────────────────────────────────────

        # `#<handle> footage <path>` — the game is already known from the segment,
        # so the whole `args` tail is the footage folder. Emits the same copyable
        # probe-command snippet as the `footage <ref> <path>` chat verb (shared
        # FootageImport builder, different dispatch).
        def handle_footage(event, args, conversation)
          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          path, force = parse_footage_args(args)
          if path.blank?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.missing_path",
              message_args: {}
            )
          end

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: :system, payload: Pito::MessageBuilder::Game::FootageImport.call(game, path: path, force: force) } ]
          )
        end

        # Splits the `footage` args tail into [path, force]. An optional `--force`
        # (or bare `force`) flag at the start or end re-probes + overwrites
        # already-imported footage; the remainder is the folder path.
        def parse_footage_args(args)
          text  = args.to_s.strip
          force = false
          force = true if text.sub!(/\A(?:--)?force\b\s*/i, "")     # leading flag
          force = true if text.sub!(/\s+(?:--)?force\b\s*\z/i, "")  # trailing flag
          [ text.strip, force ]
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
