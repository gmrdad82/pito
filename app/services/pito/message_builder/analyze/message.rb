# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Analyze
      # Builds the two `analyze` messages (roles "system" + "enhanced") in pending
      # and ready states.
      #
      # SCAFFOLD (owner-resolved): each role renders ITS ordered metrics
      # (Pito::Analytics::MetricOrder) as generic Metric::CompactComponent cells via
      # Pito::Analytics::ScaffoldComponent, every cell a `0`/`1` data-pulled flag —
      # proving the fan-out + verb + with/without work end-to-end. Roles differ by
      # their metric set + their Pito::Copy intro
      # (`pito.copy.analyze.{system,enhanced}.intro`, 50 variants each). Real
      # per-metric components come on the owner's "revisit".
      #
      # Uses a dedicated `"analyze"` marker (NOT the show-vid/game `"analytics"`
      # marker) so the two stacks stay isolated; AnalyzePrepareJob reads it to
      # rebuild the scope (level + entity_ids + period) and fill both messages.
      # Payload keys are strings so they round-trip through jsonb unchanged.
      module Message
        extend Pito::MessageBuilder::Helpers
        module_function

        INTRO_KEYS = {
          "system"   => "pito.copy.analyze.system.intro",
          "enhanced" => "pito.copy.analyze.enhanced.intro"
        }.freeze

        ROLES = INTRO_KEYS.keys.freeze
        ROLE_KINDS = { "system" => :system, "enhanced" => :enhanced }.freeze

        # Canonical predicate: a persisted event carrying an analyze marker still
        # in its pending state. Shared by the Finalizer + AnalyzePrepareJob.
        def pending?(event)
          event.payload.is_a?(Hash) && event.payload.dig("analyze", "status") == "pending"
        end

        def role(event)
          event.payload.dig("analyze", "role")
        end

        # Instant pending state — intro only; the spinner stays up until the job
        # fills the data.
        #
        # @param role       [String] "system" | "enhanced"
        # @param title      [String] the scope's display title (shimmered subject)
        # @param level      [Symbol/String] :channel | :vid | :game
        # @param entity_ids [Array<Integer>] resolved entity ids at that level
        # @param period     [String] the shift+space window token
        def pending(role:, title:, level:, entity_ids:, period:, conversation:, selection: nil)
          intro   = intro_for(role, title, period)
          payload = {
            "body"    => render_component(Pito::Analytics::ScaffoldComponent.new(intro:, pending: true)),
            "html"    => true,
            "anchor"  => true,
            "analyze" => marker("pending", role:, title:, level:, entity_ids:, period:, intro:, selection:)
          }
          # Followupable so the owner can reply `with`/`without` to mutate it in place.
          Pito::FollowUp.make_followupable!(payload, target: "analyze_message", conversation:)
        end

        # The two pending analyze events ({kind:, payload:}) — a `:system` + an
        # `:enhanced` — for one scope. Used by the chat handler AND the
        # glance→new-pair follow-up handler so both build identical messages.
        def pair(level:, entity_ids:, title:, period:, conversation:, selection: nil)
          ROLES.map do |role|
            {
              kind:    ROLE_KINDS.fetch(role),
              payload: pending(role:, title:, level:, entity_ids:, period:, conversation:, selection:)
            }
          end
        end

        # Ready state, written by AnalyzePrepareJob. Reuses the STORED intro, renders
        # the role's metrics as `0`/`1` cells, PERSISTS the scaffold map (so a mutate
        # reply re-renders without re-fetch), and PRESERVES the reply handle so the
        # message stays repliable across the pending→ready rewrite.
        #
        # @param event [Event] the pending event being filled
        # @param data  [Hash] { scaffold: {metric=>bool}, views: chart-data | nil }
        #   `views` (string-keyed: "series"/"total"/"target_daily") is the Views
        #   chart's data; persisted (with its sampled caption) so a mutate reply
        #   re-renders the chart without re-fetching.
        def ready_payload(event, data:)
          marker        = event.payload.fetch("analyze")
          scaffold      = data[:scaffold] || {}
          views         = data[:views]
          selection     = Pito::Analytics::MetricSelection.from_lists(marker["with"], marker["without"])
          views_caption = views && render_views_caption(views)
          cells         = cells_for(role: marker["role"], level: marker["level"], scaffold:, selection:, views:, views_caption:)
          analyze       = marker.merge("status" => "ready", "scaffold" => stringify_scaffold(scaffold))
          analyze["views"] = views.merge("caption" => views_caption) if views
          payload = {
            "body"    => render_component(Pito::Analytics::ScaffoldComponent.new(intro: marker["intro"], cells:)),
            "html"    => true,
            "anchor"  => true,
            "analyze" => analyze
          }
          preserve_followup(payload, event.payload)
        end

        # Re-render an already-ready analyze message in place (mutate reply) with the
        # accumulated with/without — from the PERSISTED scaffold, no re-fetch.
        # @param with/without [Array<Symbol>] the accumulated selection
        def rerender(event, with:, without:)
          marker    = event.payload.fetch("analyze")
          scaffold  = symbolize_scaffold(marker["scaffold"])
          views     = marker["views"]
          selection = Pito::Analytics::MetricSelection.from_lists(with, without)
          cells     = cells_for(role: marker["role"], level: marker["level"], scaffold:, selection:,
                                views:, views_caption: views && views["caption"])
          payload   = {
            "body"    => render_component(Pito::Analytics::ScaffoldComponent.new(intro: marker["intro"], cells:)),
            "html"    => true,
            "anchor"  => true,
            "analyze" => marker.merge("with" => with.map(&:to_s), "without" => without.map(&:to_s))
          }
          preserve_followup(payload, event.payload)
        end

        # Ordered cells for a role+level, after the with/without selection. The
        # Views metric (when its chart data is present) renders as the bespoke
        # ViewsComponent; every other metric stays a `0`/`1` scaffold cell.
        def cells_for(role:, level:, scaffold:, selection:, views: nil, views_caption: nil)
          metrics = Pito::Analytics::MetricOrder.for(role: role.to_sym, level: level.to_sym)
          metrics = Pito::Analytics::MetricSelection.apply(metrics, selection)
          metrics.map do |metric|
            if metric == :views && views.present?
              {
                chart:        :views,
                series:       Array(views["series"]),
                target_daily: views["target_daily"].to_f,
                caption:      views_caption
              }
            else
              {
                label: Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(metric)),
                value: scaffold_pulled?(scaffold, metric) ? "1" : "0"
              }
            end
          end
        end

        # The witty caption under the Views chart — metric label + compact total,
        # from the shared 50-variant dictionary (pito.copy.analyze.metric_caption).
        # Rendered like an intro: the metric name is the SUBJECT (blue→purple
        # shimmer) and the value is a cyan REFERENCE token. html-safe; persisted
        # in the marker and re-rendered raw (see ViewsComponent).
        def render_views_caption(views)
          Pito::Copy.render_html(
            "pito.copy.analyze.metric_caption",
            {
              metric: Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(:views)),
              value:  views_value_html(views)
            },
            shimmer: [ :metric ]
          )
        end

        # The caption VALUE: the cyan reference token (compact total) with the
        # trend FILLED TRIANGLE spliced directly onto it (e.g. `841K▲`). Pre-built
        # html_safe so render_html inserts it raw (no double-tokenising), which is
        # why `:value` is NOT in the `reference:` list above.
        def views_value_html(views)
          token = Pito::Shimmer::TokenComponent.html(
            Pito::Formatter::CompactCount.call(views["total"].to_i)
          )
          triangle = Pito::Analytics::Metric::TrendTriangleComponent.html(
            value: views["total"].to_i, previous: views["previous"]
          )
          token + triangle
        end

        # scaffold may arrive symbol-keyed (job) or string-keyed (persisted marker).
        def scaffold_pulled?(scaffold, metric)
          scaffold[metric] || scaffold[metric.to_s]
        end

        def stringify_scaffold(scaffold) = scaffold.transform_keys(&:to_s)
        def symbolize_scaffold(scaffold) = (scaffold || {}).transform_keys(&:to_sym)

        # Carry reply_handle/target forward so a rewritten payload stays repliable.
        def preserve_followup(payload, source_payload)
          return payload if source_payload["reply_handle"].blank?

          payload["reply_handle"] = source_payload["reply_handle"]
          payload["reply_target"] = source_payload["reply_target"]
          payload
        end

        # Entity title = subject (purple→blue); period = reference (cyan token).
        def intro_for(role, title, period)
          Pito::Copy.render_html(
            INTRO_KEYS.fetch(role.to_s),
            { title:, period: },
            shimmer:   [ :title ],
            reference: [ :period ]
          )
        end

        def marker(status, role:, title:, level:, entity_ids:, period:, intro:, selection: nil)
          {
            "status"     => status,
            "role"       => role.to_s,
            "title"      => title,
            "level"      => level.to_s,
            "entity_ids" => Array(entity_ids),
            "period"     => period,
            "intro"      => intro,
            "with"       => Array(selection&.with).map(&:to_s),
            "without"    => Array(selection&.without).map(&:to_s)
          }
        end
      end
    end
  end
end
