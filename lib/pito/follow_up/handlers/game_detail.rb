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
      #     → Delegated to Chat::Handlers::Delete via ToolDelegator.
      #
      #   #<handle> reindex
      #     → Delegated to Chat::Handlers::Reindex via ToolDelegator. The
      #       follow-up context provides the game_id so Reindex resolves the
      #       game without a ref. Emits a Voyage re-embed confirmation.
      #
      #   #<handle> link [to] [video] <id|title>
      #     → Delegated to Chat::Handlers::Link via ToolDelegator. The handler
      #       reads game_id from the source event and the video ref from rest.
      #
      # OWNER DIRECTIVE Q16/Q16b (3.8.0): `price` was previously special-cased
      # here (a direct set/unset handler, bypassing ToolDelegator); the
      # standalone `price` tool retired along with `platform` — `update` now
      # owns every game-field write, and neither survives as a card reply
      # verb (`#<handle> price 20` / `#<handle> platform ps5` are gone, not
      # redirected).
      class GameDetail < Pito::FollowUp::Handler
        self.target "game_detail"

        # @param event        [Event]        the game-detail event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)
          # tools.yml decides availability (NOT a hardcoded list — that shadowed the
          # channels/similar/vids segment tools).
          return undeclared_action(action) unless declared?(action)

          case action
          when "analyze"
            # Analyze THIS game (the detail card's single entity) — a follow-up-only
            # path (AnalyzeReply), not a chat tool, so it stays special-cased.
            Pito::FollowUp::AnalyzeReply.append(
              level: :game, ids: [ event.payload["game_id"] ].compact, conversation:, period:
            )
          else
            # Every OTHER reply tool this card declares in tools.yml (channels,
            # similar, vids/videos, at-a-glance, reindex, link/unlink,
            # shinies, sync, rm/delete, …) routes through the matrix-gated
            # ToolDelegator. tools.yml `reply.targets` is the single source of truth —
            # NEVER reintroduce a hardcoded list (it silently shadowed the segment
            # tools). Unknown actions get this target's invalid_action copy from there.
            Pito::FollowUp::ToolDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end
        end
      end
    end
  end
end
