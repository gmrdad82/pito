# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for the channel GAMES GRID (reply_target:
      # "channel_games").
      #
      # The grid is stamped `reply_target: "channel_games"` by
      # `Pito::MessageBuilder::Channel::Games.call`. The user can reply:
      #
      #   #<handle> show <id>
      #     → Show the referenced game by id (free-chat dispatch of
      #       `show game #<id>` — no follow_up scope, since the grid is a
      #       rendered component without a table_rows scope list). Returns the
      #       standard game detail + recommendations event set.
      #
      #   #<handle> @ai <text>
      #     → Delegated to Chat::Handlers::Ai via ToolDelegator — the SAME
      #       target-agnostic anchored-reply path every other rostered card
      #       takes (see Chat::Handlers::Ai's class header). WITH a
      #       follow_up context (unlike `show` above), so anchor_event_id
      #       resolves to THIS grid's own event.
      #
      # Mirrors GameSimilar (the other game-card grid) verbatim.
      class ChannelGames < Pito::FollowUp::Handler
        self.target "channel_games"

        # @param event        [Event]        the games-grid event.
        # @param rest         [String]       text after `#<handle> ` (e.g. "show 42").
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          # tools.yml decides availability — `show`/`@ai` are this card's only
          # declared tools (NOT a hardcoded check). `show` needs its own
          # no-follow-up-context dispatch; every other declared action routes
          # through the matrix-gated ToolDelegator.
          return undeclared_action(action) unless declared?(action)

          unless action == "show"
            return Pito::FollowUp::ToolDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end

          # Dispatch as free-chat (no follow_up context) so that `show game #<id>`
          # resolves the grid game by id — not the source card's channel.
          # id_only_resolution! already gates non-numeric refs before any DB call.
          # nl_eligible: false — RECONSTRUCTED body, never owner-typed free
          # text (mirrors GameSimilar; 3.0.1 reconciliation fix).
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
