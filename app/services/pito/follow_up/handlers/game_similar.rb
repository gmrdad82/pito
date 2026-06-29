# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for the SIMILAR GAMES recommendations card
      # (reply_target: "game_similar").
      #
      # The similar-games strip is stamped `reply_target: "game_similar"` by
      # `Pito::MessageBuilder::Game::SimilarGames.call`. The user can reply:
      #
      #   #<handle> show <id>
      #     → Show the referenced similar game by id (free-chat dispatch of
      #       `show game #<id>` — no follow_up scope, since the strip is a
      #       rendered component without a table_rows scope list). Returns the
      #       standard game detail + recommendations event set.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Game` for the model.
      class GameSimilar < Pito::FollowUp::Handler
        self.target "game_similar"
        self.mode   :append
        self.actions "show"

        # @param event        [Event]        the similar-games strip event.
        # @param rest         [String]       text after `#<handle> ` (e.g. "show 42").
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          unless action == "show"
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_similar.errors.invalid_action",
              message_args: { action: action }
            )
          end

          # Dispatch as free-chat (no follow_up context) so that `show game #<id>`
          # resolves the SIMILAR game by id — not the source card's game_id.
          # id_only_resolution! already gates non-numeric refs before any DB call.
          result = Pito::Chat::Dispatcher.call(
            input:          "show game #{args}",
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
