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

        def call(event:, rest:, conversation:, period: nil, **)
          action, args = parse_rest(rest)
          # verbs.yml decides availability (the matrix), not a hardcoded list.
          return undeclared_action(action) unless declared?(action)

          scope = resolve_scope(event)
          return scope_not_found if scope.nil?

          # Bare `analyze` re-runs the full analysis (no metric filtering); with /
          # without carry a metric selection.
          selection = action == "analyze" ? nil : build_selection(action, args)

          pair = Pito::MessageBuilder::Analyze::Message.pair(
            level:        scope[:level],
            entity_ids:   scope[:ids],
            title:        scope[:title],
            period:       period.presence || conversation.stats_period,
            conversation:,
            selection:    selection
          )

          Pito::FollowUp::Result::Append.new(events: pair)
        end

        private

        PLURALS = { vid: "vids", game: "games", channel: "channels" }.freeze
        MODELS  = { "Video" => ::Video, "Game" => ::Game, "Channel" => ::Channel }.freeze
        LEVELS  = { "Video" => :vid, "Game" => :game, "Channel" => :channel }.freeze

        # Entity/entities from the glance's analytics marker → { level:, ids:, title: }.
        # Handles a single glance (scope_id) AND a combined multi-id glance (scope_ids)
        # so `analyze` / `with` / `without` on either re-runs over the same scope.
        def resolve_scope(event)
          marker = event.payload["analytics"] || {}
          model  = MODELS[marker["scope_type"]]
          return nil unless model

          ids     = marker["scope_ids"].presence || Array(marker["scope_id"]).compact
          records = model.where(id: ids).to_a
          return nil if records.empty?

          level = LEVELS.fetch(marker["scope_type"], :vid)
          { level:, ids: records.map(&:id), title: scope_title(level, records) }
        end

        # One entity's name/handle, or "N vids/games/channels" for a set.
        def scope_title(level, records)
          if records.one?
            r = records.first
            return r.respond_to?(:at_handle) ? r.at_handle : r.title
          end
          "#{records.size} #{PLURALS.fetch(level, level.to_s)}"
        end

        def build_selection(action, args)
          metrics = Pito::Analytics::MetricSelection.symbolize(args.to_s.split(/[\s,]+/))
          if action == "with"
            Pito::Analytics::MetricSelection::Selection.new(with: metrics, without: [])
          else
            Pito::Analytics::MetricSelection::Selection.new(with: [], without: metrics)
          end
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
