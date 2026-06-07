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
      #   #<handle> similar [filters]
      #     → Parse optional `key=value` filters (genre/year/developer/publisher/
      #       platform/score/ttb/complexity), call `Pito::Recommendations.similar_games`,
      #       render a ScoreBarComponent segment per hit, and MUTATE the enhanced
      #       message body to show the results. Does NOT consume (chainable; running
      #       `channel` next swaps/updates the segment area).
      #
      #   #<handle> channel
      #     → `Pito::Recommendations.channels_for(game)`, render a ScoreBarComponent
      #       per channel result, and MUTATE the enhanced message body.
      #       Also chainable (running `similar` after `channel` works).
      #
      # == Mode
      #
      # Declared as `:mutate`.  The `reindex` action returns `Result::Append`
      # directly — the dispatch job inspects the result type and dispatches
      # accordingly.
      #
      # == Chaining
      #
      # Both `similar` and `channel` retain `reply_handle` + `reply_target` and
      # do NOT set `reply_consumed`, so the message stays repliable after each
      # call. Running `similar` after `channel` (or vice-versa) replaces the
      # rendered segment area. The `game_id` is also preserved in each mutation
      # payload so subsequent calls can still resolve the game.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Game` for the model and `::Game::VoyageIndexer` for the
      # indexer.
      class GameEnhanced < Pito::FollowUp::Handler
        self.target "game_enhanced"
        self.mode   :mutate
        self.actions "reindex", "similar", "channel"

        # Key-value filter tokens accepted by `similar [filters]`.
        # Maps the user-facing key (or alias) to the canonical key expected by
        # `Pito::Recommendations.similar_games(game, filters:)`.
        FILTER_KEY_MAP = {
          "genre"       => :genre,
          "year"        => :year,
          "developer"   => :developer,
          "publisher"   => :publisher,
          "platform"    => :platform,
          "score"       => :score,
          "ttb"         => :ttb,
          "complexity"  => :complexity
        }.freeze

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

          case action
          when "reindex"
            handle_reindex(event, game, conversation)
          when "similar"
            handle_similar(event, game, args, conversation)
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

        # ── reindex ────────────────────────────────────────────────────────────

        def handle_reindex(event, game, conversation)
          payload = Pito::MessageBuilder::Game::ReindexConfirmation.call(game, conversation:)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "confirmation", payload: payload } ]
          )
        end

        # ── similar [filters] ──────────────────────────────────────────────────

        def handle_similar(event, game, args, conversation)
          filters = parse_filters(args)
          results = Pito::Recommendations.similar_games(game, filters: filters)
          original_handle = event.payload["reply_handle"].to_s

          new_payload = Pito::MessageBuilder::Game::EnhancedSegments.call(
            event: event, game: game, results: results,
            result_type: :similar, original_handle: original_handle
          )

          Pito::FollowUp::Result::Mutation.new(kind: "system", payload: new_payload)
        end

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

        # Parse `key=value` tokens from the filter string.
        # Unrecognised keys are silently ignored (future-proof per Recommendations doc).
        # "similar genre=action year=2020 score=70" → { genre: "action", year: "2020", score: "70" }
        def parse_filters(args)
          return {} if args.blank?

          args.to_s.scan(/(\w+)=(\S+)/).each_with_object({}) do |(raw_key, value), hash|
            canonical = FILTER_KEY_MAP[raw_key.downcase]
            hash[canonical] = value if canonical
          end
        end
      end
    end
  end
end
