# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for the import-done event (reply_target: "game_imported").
      #
      # The done message is stamped `reply_target: "game_imported"` by
      # `Pito::MessageBuilder::Game::ImportDone`. The user can reply ONLY:
      #
      #   #<handle> show   → shows the imported/resynced game
      #     Translates to `show game #<game_id>` using game_id from the event payload.
      #     No args needed — the game_id is already in context.
      class GameImported < Pito::FollowUp::Handler
        self.target "game_imported"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, _args = parse_rest(rest)

          unless action == "show"
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_imported.errors.invalid_action",
              message_args: { action: action }
            )
          end

          game_id = event.payload["game_id"]

          result = Pito::Chat::Dispatcher.call(
            input:          "show game ##{game_id}",
            conversation:   conversation,
            channel:        channel,
            period:         period,
            viewport_width: viewport_width
          )
          Pito::FollowUp::ChatResultAdapter.call(result)
        end
      end
    end
  end
end
