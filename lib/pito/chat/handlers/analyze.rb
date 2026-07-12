# frozen_string_literal: true

# Handler for the `analyze` chat tool (aliases: `analytics`, `stats`).
#
# Interval-aware YouTube analytics scoped to a channel, vid, or game. Resolves the
# scope via Pito::Analytics::ScopeResolver (entity arg + shift+tab channel scope),
# the period from shift+space (conversation.stats_period). On a resolvable scope it
# parses a Pito::Chat::SegmentSelection (segments `numbers` → the :system card,
# `breakdowns` → the :enhanced card) and emits ONLY the selected pending message(s)
# — each with its own Pito::Copy intro — then returns immediately; the Finalizer
# enqueues AnalyzePrepareJob, which fans out per-video / per-channel primitives,
# fills each created message from the per-metric stashes, and resolves each
# message's own thinking indicator (so each "thought for xx.xxs" spans its full
# fan-out). Bare `analyze` → numbers only; `full` → both; `with`/`only` per the
# selection. Conflicting or unknown segment tokens surface the shared segment error
# copy. Metric tokens (`with views`, `without comments`) are fed to SegmentSelection
# as extra_vocabulary so they never read as unknown segments; MetricSelection.parse
# reads the same raw independently. Bare `analyze` suggests options; an unresolvable
# scope surfaces the matching error copy.
module Pito
  module Chat
    module Handlers
      class Analyze < Pito::Chat::Handler
        self.tool = :analyze
        self.description_key = "pito.chat.analyze.descriptions.analyze"

        PLURALS = { "channel" => "channels", "vid" => "vids", "game" => "games" }.freeze

        def call
          result = Pito::Analytics::ScopeResolver.call(
            raw: message.raw, channel_scope: channel.presence || conversation.scope_channel
          )

          case result.status
          when :ok    then ok_events(result)
          when :error then text_event("errors.#{result.error_key}", **result.error_args)
          else             text_event("suggest")
          end
        end

        # Public seam for Pito::Chat::Handlers::SegmentTool. Runs
        # `analyze` forcing an `only <segment>` selection and returns the same
        # Result the typed `analyze <noun> <ref> only <segment>` form produces —
        # scope resolution, emission, and error copy all flow through the unchanged
        # path. Off (@forced_segment nil) in the normal typed/reply path.
        def drive_segment(segment)
          @forced_segment = segment
          call
        end

        private

        # The selected pending card(s) — `numbers` (:system) and/or `breakdowns`
        # (:enhanced); AnalyzePrepareJob (enqueued by the Finalizer's analyze-pending
        # gate) fans out only over each created message's own metric_keys, fills +
        # resolves each. Segment selection (which cards exist) is independent of the
        # MetricSelection filter (which metrics render inside a card).
        def ok_events(result)
          entity_kind = result.level
          selection   = resolved_selection(entity_kind)
          return segment_conflict_error if selection.conflict
          return segment_unknown_error(selection.unknown, entity_kind) if selection.unknown.any?

          events = Pito::MessageBuilder::Analyze::Message.pair(
            level:        result.level,
            entity_ids:   result.scopes.map(&:id),
            title:        scope_title(result),
            period:       analytics_period,
            conversation:,
            selection:    Pito::Analytics::MetricSelection.parse(message.raw),
            roles:        Pito::MessageBuilder::Analyze::Message.roles_for(selection.names)
          )

          # Append segments footer to the first emitted message.
          if events.any?
            all_names = Pito::Chat::Segments.names(tool: :analyze, entity: entity_kind)
            addable   = all_names - selection.names
            removable = selection.names & all_names
            footer    = Pito::Lists::OptionsFooter.call(
              addable:   addable,
              removable: removable,
              sort_keys: [],
              noun:      "segments"
            )
            events.first[:payload]["list_footer"] = footer if footer
          end

          Pito::Chat::Result::Ok.new(events:)
        end

        # The segment selection to emit. Normally the trailing-clause parse (with
        # metric tokens shielded as extra_vocabulary). When a segment tool forced a
        # single segment (drive_segment), returns the SAME Selection `only
        # <segment>` would parse to for this entity, byte-identical to the typed
        # `analyze <noun> <ref> only <segment>` form.
        def resolved_selection(entity_kind)
          return Pito::Chat::SegmentSelection.only(tool: :analyze, entity: entity_kind, segment: @forced_segment) if @forced_segment

          Pito::Chat::SegmentSelection.parse(
            message.raw, tool: :analyze, entity: entity_kind, extra_vocabulary: metric_vocabulary
          )
        end

        # Metric tokens overlap the raw string with SegmentSelection's clause parse.
        # Feeding MetricSelection's vocabulary (aliases + canonical metric keys) as
        # extra_vocabulary keeps a metric token (e.g. `views`) from being flagged as
        # an unknown segment — the two parsers read the same raw independently.
        def metric_vocabulary
          Pito::Analytics::MetricSelection::ALIASES.keys +
            Pito::Analytics::MetricOrder::METRICS.keys.map(&:to_s)
        end

        # Segment error copy — mirrors the show handler's exact idiom so `analyze`
        # and `show` report conflicting / unknown segment tokens identically.
        def segment_conflict_error
          Pito::Chat::Result::Error.new(
            message_key: Pito::Copy.render("pito.copy.segments.conflict"),
            message_args: {}
          )
        end

        def segment_unknown_error(unknowns, entity_kind)
          Pito::Chat::Result::Error.new(
            message_key: Pito::Copy.render(
              "pito.copy.segments.unknown",
              tokens: unknowns.join(", "),
              names:  Pito::Chat::Segments.names(tool: :analyze, entity: entity_kind).join(", ")
            ),
            message_args: {}
          )
        end

        def text_event(key, **args)
          payload = Pito::MessageBuilder::Text.call("pito.copy.analyze.#{key}", **args)
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end

        # Display title for the scope: a single entity's name/handle, or "N <plural>".
        def scope_title(result)
          scopes = result.scopes
          return "your #{PLURALS.fetch(result.level.to_s, "channels")}" if scopes.empty?
          return entity_title(scopes.first) if scopes.one?

          "#{scopes.size} #{PLURALS.fetch(result.level.to_s, result.level.to_s)}"
        end

        def entity_title(entity)
          entity.respond_to?(:at_handle) ? entity.at_handle : entity.title
        end

        def analytics_period
          period.presence || conversation.stats_period
        end
      end
    end
  end
end
