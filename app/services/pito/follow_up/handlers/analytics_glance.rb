# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for the show vid/game analytics glance
      # (reply_target: "analytics_glance").
      #
      # Replying `#<handle> with <metrics>` / `#<handle> without <metrics>` emits a
      # NEW analyze pair (`:system` + `:enhanced`) on that entity with the selection
      # applied. Because the pair lands as a fresh `:system` turn, the Finalizer's
      # consume mechanism retires ALL prior live handles (the whole show vid/game
      # turn — detail, linked-game/videos, recommendations, glance) on its own — the
      # show is "done", you're in analyze now. The new pair carries fresh handles
      # (repliable → mutate).
      #
      # The entity is inferred from the glance's `analytics` marker (scope_type/scope_id).
      # NAMESPACE: use `::Video`/`::Game` for models; `Pito::*` for services.
      class AnalyticsGlance < Pito::FollowUp::Handler
        self.target "analytics_glance"
        self.mode   :append
        self.actions "with", "without", "analyze"

        def call(event:, rest:, conversation:, period: nil, **)
          action, args = parse_rest(rest)
          return invalid_action(action) unless %w[with without analyze].include?(action)

          scope = resolve_scope(event)
          return scope_not_found if scope.nil?

          # Bare `analyze` re-runs the full analysis (no metric filtering); with /
          # without carry a metric selection.
          selection = action == "analyze" ? nil : build_selection(action, args)

          pair = Pito::MessageBuilder::Analyze::Message.pair(
            level:        scope[:level],
            entity_ids:   [ scope[:id] ],
            title:        scope[:title],
            period:       period.presence || conversation.stats_period,
            conversation:,
            selection:    selection
          )

          Pito::FollowUp::Result::Append.new(events: pair)
        end

        private

        # Entity from the glance's analytics marker → { level:, id:, title: }.
        def resolve_scope(event)
          marker = event.payload["analytics"] || {}
          record =
            case marker["scope_type"]
            when "Video"   then ::Video.find_by(id: marker["scope_id"])
            when "Game"    then ::Game.find_by(id: marker["scope_id"])
            when "Channel" then ::Channel.find_by(id: marker["scope_id"])
            end
          return nil unless record

          level =
            case marker["scope_type"]
            when "Game"    then :game
            when "Channel" then :channel
            else                :vid
            end

          {
            level: level,
            id:    record.id,
            title: record.respond_to?(:at_handle) ? record.at_handle : record.title
          }
        end

        def build_selection(action, args)
          metrics = Pito::Analytics::MetricSelection.symbolize(args.to_s.split(/[\s,]+/))
          if action == "with"
            Pito::Analytics::MetricSelection::Selection.new(with: metrics, without: [])
          else
            Pito::Analytics::MetricSelection::Selection.new(with: [], without: metrics)
          end
        end

        def invalid_action(action)
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.analytics_glance.errors.invalid_action",
            message_args: { action: }
          )
        end

        def scope_not_found
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.analytics_glance.errors.scope_not_found",
            message_args: {}
          )
        end
      end
    end
  end
end
