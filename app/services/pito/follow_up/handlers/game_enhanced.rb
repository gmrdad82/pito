# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for game-enhanced events (reply_target: "game_enhanced").
      #
      # The enhanced message is stamped `reply_target: "game_enhanced"` by
      # `GameImportJob` after the full 5-step import flow. The user can reply:
      #
      #   #<handle> reindex
      #     → Emit a confirmation event (`command: "game_reindex"`) whose executor
      #       branch calls `Game::VoyageIndexer.call(game, force: true)`.
      #       Mode: append — the confirmation lands as a new event below the card.
      #
      #   #<handle> channel
      #     → `Pito::Recommendations.channels_for(game)`, render a ScoreBarComponent
      #       per channel result, and MUTATE the enhanced message body.
      #       Chainable: retains `reply_handle` + `reply_target` and does NOT set
      #       `reply_consumed`. The `game_id` is preserved in the mutation payload
      #       so subsequent calls can still resolve the game.
      #
      # == Mode
      #
      # Declared as `:mutate`.  The `reindex` action returns `Result::Append`
      # directly — the dispatch job inspects the result type and dispatches
      # accordingly.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Game` for the model and `::Game::VoyageIndexer` for the
      # indexer.
      class GameEnhanced < Pito::FollowUp::Handler
        self.target "game_enhanced"
        self.mode   :mutate
        self.actions "reindex", "channel"

        # @param event        [Event]        the game-enhanced event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Mutation | Result::Error]
        def call(event:, rest:, conversation:)
          action, args = parse_rest(rest)

          game = resolve_game_from_event(event)
          if game.nil?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_enhanced.errors.game_not_found",
              message_args: {}
            )
          end

          if action == "reindex"
            return Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:)
          end

          case action
          when "channel"
            handle_channel(event, game, conversation)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_enhanced.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # ── channel ────────────────────────────────────────────────────────────

        def handle_channel(event, game, conversation)
          results = Pito::Recommendations.channels_for(game)
          original_handle = event.payload["reply_handle"].to_s

          new_payload = Pito::MessageBuilder::Game::EnhancedSegments.call(
            event: event, game: game, results: results,
            result_type: :channel, original_handle: original_handle
          )

          Pito::FollowUp::Result::Mutation.new(kind: "system", payload: new_payload)
        end

        # ── helpers ────────────────────────────────────────────────────────────

        def resolve_game_from_event(event)
          payload = event.payload.with_indifferent_access
          game_id = payload[:game_id]
          return nil unless game_id.present?

          ::Game.find_by(id: game_id)
        end
      end
    end
  end
end
