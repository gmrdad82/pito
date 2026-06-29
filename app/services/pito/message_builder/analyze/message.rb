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
      #
      # Chart metrics (views / watched_hours / subs): `:system` role only, rendered
      # as Pito::Analytics::Metric::AreaChart (braille area chart). Each chart's
      # data is persisted in the marker under its metric name (string key) so a
      # mutate reply re-renders the chart without re-fetching. CHART_METRIC_KEYS
      # lists the metrics that may carry chart data.
      module Message
        extend Pito::MessageBuilder::Helpers
        module_function

        INTRO_KEYS = {
          "system"   => "pito.copy.analyze.system.intro",
          "enhanced" => "pito.copy.analyze.enhanced.intro"
        }.freeze

        ROLES = INTRO_KEYS.keys.freeze
        ROLE_KINDS = { "system" => :system, "enhanced" => :enhanced }.freeze

        # Metrics that render as bespoke AreaChart cells in the :system role.
        CHART_METRIC_KEYS = %w[views watched_hours subs avg_view_duration avg_viewed_pct].freeze

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
        # the role's metrics as `0`/`1` cells or AreaChart cells (for views /
        # watched_hours / subs in the :system role), PERSISTS the scaffold map and
        # chart data (so a mutate reply re-renders without re-fetch), and PRESERVES
        # the reply handle so the message stays repliable across the pending→ready
        # rewrite.
        #
        # @param event [Event] the pending event being filled
        # @param data  [Hash] { scaffold: {metric=>bool}, charts: {metric=>chart_hash}|nil }
        #   `charts` is a hash from metric symbol (e.g. :views) to a string-keyed
        #   chart-data hash { "series", "total", "previous", "target_daily" } — or nil
        #   when no chart data is available (e.g. enhanced role, or fetch error).
        def ready_payload(event, data:)
          marker   = event.payload.fetch("analyze")
          scaffold = data[:scaffold] || {}
          charts   = data[:charts] || {}
          selection = Pito::Analytics::MetricSelection.from_lists(marker["with"], marker["without"])

          chart_captions = charts.each_with_object({}) do |(metric, chart), h|
            h[metric.to_sym] = chart && render_chart_caption(metric:, chart:)
          end

          likes   = likes_marker(data[:likes])
          cells   = cells_for(role: marker["role"], level: marker["level"], scaffold:, selection:, charts:, chart_captions:, likes:)
          analyze = marker.merge("status" => "ready", "scaffold" => stringify_scaffold(scaffold))

          # Persist each chart (with its sampled caption) so a mutate reply
          # can re-render the chart without re-fetching from YouTube.
          charts.each do |metric, chart|
            analyze[metric.to_s] = chart.merge("caption" => chart_captions[metric.to_sym]) if chart
          end
          # Persist the likes hearts (+ caption) so a mutate reply re-renders without refetch.
          analyze["likes"] = likes if likes

          payload = {
            "body"    => render_component(Pito::Analytics::ScaffoldComponent.new(intro: marker["intro"], cells:)),
            "html"    => true,
            "anchor"  => true,
            "analyze" => analyze
          }
          preserve_followup(payload, event.payload)
        end

        # Re-render an already-ready analyze message in place (mutate reply) with the
        # accumulated with/without — from the PERSISTED scaffold + chart data, no re-fetch.
        # @param with/without [Array<Symbol>] the accumulated selection
        def rerender(event, with:, without:)
          marker    = event.payload.fetch("analyze")
          scaffold  = symbolize_scaffold(marker["scaffold"])
          selection = Pito::Analytics::MetricSelection.from_lists(with, without)

          # Read charts from the persisted marker (string-keyed; captions included).
          charts = CHART_METRIC_KEYS.each_with_object({}) do |key, h|
            h[key.to_sym] = marker[key] if marker[key].present?
          end
          chart_captions = charts.transform_values { |chart| chart&.fetch("caption", nil) }

          cells   = cells_for(role: marker["role"], level: marker["level"], scaffold:, selection:, charts:, chart_captions:, likes: marker["likes"])
          payload = {
            "body"    => render_component(Pito::Analytics::ScaffoldComponent.new(intro: marker["intro"], cells:)),
            "html"    => true,
            "anchor"  => true,
            "analyze" => marker.merge("with" => with.map(&:to_s), "without" => without.map(&:to_s))
          }
          preserve_followup(payload, event.payload)
        end

        # Ordered cells for a role+level, after the with/without selection. Metrics
        # that have chart data (views / watched_hours / subs) render as AreaChart
        # cells; every other metric stays a `0`/`1` scaffold cell.
        #
        # @param charts         [Hash{Symbol=>Hash}] metric → chart data (string-keyed)
        # @param chart_captions [Hash{Symbol=>String}] metric → pre-rendered caption html
        def cells_for(role:, level:, scaffold:, selection:, charts: {}, chart_captions: {}, likes: nil)
          metrics = Pito::Analytics::MetricOrder.for(role: role.to_sym, level: level.to_sym)
          metrics = Pito::Analytics::MetricSelection.apply(metrics, selection)
          metrics.map do |metric|
            chart = charts[metric]
            if metric == :likes && likes_hearts?(likes)
              heart_cell(likes)
            elsif chart.present?
              {
                chart:           metric,
                series:          Array(chart["series"]),
                target_daily:    chart["target_daily"].to_f,
                caption:         chart_captions[metric],
                trend:           chart.fetch("trend", true),
                reference_token: chart["reference_token"],
                dates:           chart["dates"]
              }
            else
              {
                label: Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(metric)),
                value: scaffold_pulled?(scaffold, metric) ? "1" : "0"
              }
            end
          end
        end

        # The persisted likes marker carries hearts? `likes` is the string-keyed
        # `{ "hearts" => [...], "caption" => html }` hash (or nil).
        def likes_hearts?(likes)
          likes.is_a?(Hash) && Array(likes["hearts"]).any?
        end

        # Build the HEART grid cell from the persisted likes marker — symbolises the
        # stored colour + keys for HeartChartComponent.
        def heart_cell(likes)
          hearts = Array(likes["hearts"]).map do |h|
            {
              score:    h["score"],
              color:    h["color"].to_s.to_sym,
              likes:    h["likes"],
              dislikes: h["dislikes"]
            }
          end
          { heart: hearts, caption: likes["caption"] }
        end

        # Build the persisted likes marker (string-keyed, jsonb-safe) from the job's
        # likes data — an Array of { score:, color:, likes:, dislikes: } or nil.
        # The caption is sampled once here (from the SUBJECT heart's score).
        def likes_marker(likes_data)
          return nil if likes_data.blank?

          {
            "hearts"  => likes_data.map do |h|
              { "score" => h[:score], "color" => h[:color].to_s, "likes" => h[:likes], "dislikes" => h[:dislikes] }
            end,
            "caption" => render_likes_caption(score: likes_data.first[:score]).to_s
          }
        end

        # The witty caption under an AreaChart — metric label + compact value (with
        # optional trend triangle), from the shared 50-variant dictionary
        # (pito.copy.analyze.metric_caption). The metric name is the SUBJECT
        # (blue→purple shimmer) and the value is a cyan REFERENCE token.
        # html-safe; persisted in the marker and re-rendered raw.
        #
        # `trend:` is read from `chart["trend"]` (default true). When false the
        # trend triangle is suppressed (e.g. avg_view_duration, avg_viewed_pct).
        # `chart["reference_token"]` adds an extra cyan shimmer token after the
        # value (e.g. "lifetime" for avg_viewed_pct).
        #
        # @param metric [Symbol]
        # @param chart  [Hash]   string-keyed chart data
        def render_chart_caption(metric:, chart:)
          caption = Pito::Copy.render_html(
            "pito.copy.analyze.metric_caption",
            {
              metric: Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(metric.to_sym)),
              value:  chart_value_html(metric:, chart:)
            },
            shimmer: [ :metric ]
          )

          if metric.to_sym == :avg_viewed_pct
            insight = render_retention_insight(chart:)
            caption = (caption + "<br>".html_safe + insight).html_safe if insight
          end

          caption
        end

        # The witty caption under the likes-hearts (HeartChartComponent) — the
        # SUBJECT ("Likes vs Dislikes", blue→purple shimmer) + the score% as a cyan
        # token followed by the cyan "lifetime" reference. Mirrors
        # render_chart_caption's render_html/shimmer path; html-safe; persisted in
        # the marker and re-rendered raw. Shared by the analyze grid (LIKES3), the
        # demo, and the isolation preview so the caption is never hand-tuned.
        #
        # @param score [Numeric] 0..100 likes-vs-dislikes %
        # @param label [String]  the subject label (default "Likes vs Dislikes")
        def render_likes_caption(score:, label: "Likes vs Dislikes")
          pct   = format("%.1f%%", score.to_f.clamp(0.0, 100.0))
          value = Pito::Shimmer::TokenComponent.html(pct) +
                  " ".html_safe + Pito::Shimmer::TokenComponent.html("lifetime")

          Pito::Copy.render_html(
            "pito.copy.analyze.likes_caption",
            { metric: label, value: value },
            shimmer: [ :metric ]
          )
        end

        # The caption VALUE: the cyan reference token (compact total) with an
        # optional trend FILLED TRIANGLE (e.g. `841K▲`) and an optional extra
        # reference token (e.g. "lifetime"). Pre-built html_safe so render_html
        # inserts it raw (no double-tokenising).
        #
        # @param metric [Symbol]
        # @param chart  [Hash]   string-keyed { "total"|"total_pct", "previous",
        #                        "trend", "reference_token", "avg_duration_seconds" }
        def chart_value_html(metric:, chart:)
          trend            = chart.fetch("trend", true)
          reference_token  = chart["reference_token"]

          token = Pito::Shimmer::TokenComponent.html(fmt_chart_value(metric, chart))

          triangle = if trend
            Pito::Analytics::Metric::TrendTriangleComponent.html(
              value:    (chart["total"] || chart["total_pct"]).to_f,
              previous: chart["previous"]
            )
          else
            ActiveSupport::SafeBuffer.new
          end

          ref = if reference_token.present?
            " ".html_safe + Pito::Shimmer::TokenComponent.html(reference_token)
          else
            ActiveSupport::SafeBuffer.new
          end

          token + triangle + ref
        end

        # Second caption row for avg_viewed_pct: Studio-style retention insight.
        # "X% of viewers are still watching at around the M:SS mark, which is <benchmark>."
        # Returns nil when required data is missing (safe no-op).
        def render_retention_insight(chart:)
          at_mark_pct = chart["at_mark_pct"]
          benchmark_w = chart["benchmark_word"]
          return nil if at_mark_pct.nil? || benchmark_w.nil?

          mark           = Pito::Formatter::Duration.call(chart["avg_duration_seconds"].to_f) || "0:00"
          benchmark_html = benchmark_word_html(benchmark_w)

          # The "X%" reads as the SUBJECT here (owner) — wrap it in the subject
          # shimmer (purple→blue), like the metric subject token. The "%" is part
          # of the shimmered value (templates use bare %{pct}); benchmark stays its
          # own trend-coloured span.
          Pito::Copy.render_html(
            "pito.copy.analyze.retention_insight",
            { pct: "#{at_mark_pct.to_i}%", mark:, benchmark: benchmark_html },
            shimmer: [ :pct ]
          )
        end

        # Wrap the benchmark word in a colored span matching the trend-arrow CSS.
        # above average → pito-trend-number--up (green shimmer)
        # below average → pito-trend-number--down (red shimmer)
        # typical       → pito-trend-number (neutral fg-default)
        # Returns an html_safe SafeBuffer so render_html inserts it raw (not double-escaped).
        def benchmark_word_html(word)
          css_class = case word
          when "above average" then "pito-trend-number pito-trend-number--up"
          when "below average" then "pito-trend-number pito-trend-number--down"
          else "pito-trend-number"
          end

          ActionController::Base.helpers.tag.span(word, class: css_class)
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

        # Format the caption value string for a metric. Dispatches by metric symbol:
        #   :views            → compact count ("841K")
        #   :watched_hours    → rounded hours ("42h")
        #   :subs             → net change, sign-preserving ("-42" or "123")
        #   :avg_view_duration→ M:SS duration ("2:05")
        #   :avg_viewed_pct   → "M:SS (XX.X%)" — lifetime avg duration + avg retention
        #
        # @param metric [Symbol]
        # @param chart  [Hash] string-keyed chart data (reads "total", "total_pct",
        #                      "avg_duration_seconds" depending on metric)
        def fmt_chart_value(metric, chart)
          case metric.to_sym
          when :watched_hours
            "#{chart["total"].to_f.round}h"
          when :subs
            v = chart["total"].to_i
            v.negative? ? "-#{Pito::Formatter::CompactCount.call(v.abs)}" : Pito::Formatter::CompactCount.call(v)
          when :avg_view_duration
            Pito::Formatter::Duration.call(chart["total"].to_f) || "0:00"
          when :avg_viewed_pct
            dur_s = Pito::Formatter::Duration.call(chart["avg_duration_seconds"].to_f) || "0:00"
            pct   = format("%.1f%%", chart["total_pct"].to_f)
            "#{dur_s} (#{pct})"
          else
            Pito::Formatter::CompactCount.call(chart["total"].to_i)
          end
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
