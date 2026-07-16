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

          # tools.yml decides availability — `show` is this card's only declared tool
          # (NOT a hardcoded check). `show` needs its own no-follow-up-context dispatch.
          return undeclared_action(action) unless declared?(action)

          game_id = event.payload["game_id"]

          # nl_eligible: false — RECONSTRUCTED body, never owner-typed free
          # text; the id is always numeric here so nl_soft_fail_ref? would
          # never fire anyway, but this keeps the contract consistent with the
          # other show-dispatching follow-up handlers (3.0.1 reconciliation fix).
          result = Pito::Dispatch::Router.call(
            input:          "show game ##{game_id}",
            conversation:   conversation,
            channel:        channel,
            period:         period,
            viewport_width: viewport_width,
            nl_eligible:    false
          )
          Pito::FollowUp::ChatResultAdapter.call(result)
        end
      end
    end
  end
end
