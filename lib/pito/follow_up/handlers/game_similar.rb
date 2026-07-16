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
      class GameSimilar < Pito::FollowUp::Handler
        self.target "game_similar"

        # @param event        [Event]        the similar-games strip event.
        # @param rest         [String]       text after `#<handle> ` (e.g. "show 42").
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          # tools.yml decides availability — `show` is this card's only declared tool
          # (NOT a hardcoded check). `show` needs its own no-follow-up-context dispatch.
          return undeclared_action(action) unless declared?(action)

          # Dispatch as free-chat (no follow_up context) so `show game <ref>`
          # resolves against the whole library — the SIMILAR game the user
          # names, not the source card's game_id. `ref` is a numeric id OR
          # (since P36) a game title: this path inherits `show`'s title
          # resolution because it dispatches the same free-chat input a user
          # would type; a ref matching neither an id nor a title returns the
          # standard not-found Ok. nl_eligible: false — this body is
          # RECONSTRUCTED from the reply, never owner-typed free text, so a
          # title-ladder miss must stay that crisp not-found (consume: false),
          # never soft-fail into the NL gate (3.0.1 reconciliation fix).
          result = Pito::Dispatch::Router.call(
            input:          "show game #{args}",
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
