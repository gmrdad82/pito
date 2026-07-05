# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Analyze
      # Builds the two `analyze` messages (roles "system" + "enhanced") in pending
      # and ready states.
      #
      # SCAFFOLD (owner-resolved): each role renders ITS ordered metrics
      # (Pito::Analytics::MetricOrder) as generic Slots::Compact cells via
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
      # as Pito::Analytics::Visualizers::Area (braille area chart). Each chart's
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

        # Metrics that render as bespoke AreaChart cells (persisted + re-rendered on
        # mutate replies). views…avg_viewed_pct are :system; retention + comments are
        # :enhanced (comments moved scalar → Area, LAST enhanced metric, 2026-07-01).
        CHART_METRIC_KEYS = %w[views watched_hours subs avg_view_duration avg_viewed_pct retention comments day_of_week_heatmap].freeze

        # Metrics that render as bespoke BarChart cells (share breakdowns).
        BAR_METRIC_KEYS = %w[subscribed_status devices geography demographics_gender demographics_age].freeze

        # Metrics that render as a bespoke chart (Area / Heart / Bar). When such a
        # metric has NO data, its cell becomes the NoData placeholder instead of the
        # "0"/compact scalar (owner: NoData covers every empty Area/Heart/Bar). Pure
        # scalar metrics (day_of_week_heatmap) stay 0/1.
        NO_DATA_METRICS = (CHART_METRIC_KEYS.map(&:to_sym) + %i[likes] + BAR_METRIC_KEYS.map(&:to_sym)).freeze

        # Fixed key→colour token maps for the categorical bar metrics (the
        # Pito::Analytics::Visualizers::Bar COLOR_TOKENS palette). geography + age have dynamic keys
        # → coloured by ORDER from a ramp instead (GEO_RAMP / AGE_RAMP).
        BAR_COLORS = {
          subscribed_status:   { "SUBSCRIBED" => :green, "UNSUBSCRIBED" => :red },
          devices:             { "MOBILE" => :blue, "DESKTOP" => :purple, "TV" => :cyan },
          demographics_gender: { "male" => :blue, "female" => :pink, "gender_other" => :purple }
        }.freeze
        GEO_RAMP = %i[green cyan blue purple orange].freeze
        AGE_RAMP = %i[cyan blue purple pink yellow].freeze

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
          intro       = intro_for(role, title, period)
          token       = SecureRandom.hex(4)
          # The ordered metrics the fan-out fills (the full role+level set; the
          # with/without selection only filters the final render, not the fetch).
          metric_keys = Pito::Analytics::MetricOrder.for(role: role.to_sym, level: level.to_sym).map(&:to_s)
          payload = {
            "body"    => render_component(Pito::Analytics::ScaffoldComponent.new(intro:, pending: true, token:, metric_keys:)),
            "html"    => true,
            "anchor"  => true,
            "analyze" => marker("pending", role:, title:, level:, entity_ids:, period:, intro:, selection:, token:, metric_keys:)
          }
          # Followupable so the owner can reply `with`/`without` to mutate it in place.
          Pito::FollowUp.make_followupable!(payload, target: "analyze_message", conversation:)
        end

        # Map selected segment names (a Pito::Chat::SegmentSelection result) to
        # scaffold roles, in canonical ROLES order. Names outside segment_roles are
        # ignored (the analyze handler validates + reports unknowns before this).
        def roles_for(names)
          wanted = Array(names).filter_map { |n| segment_roles[n.to_s] }.to_set
          ROLES.select { |role| wanted.include?(role) }
        end

        # Derives the segment-name → role mapping from the analyze verb's config.
        # Replaces the former SEGMENT_ROLES constant — now read from verbs.yml.
        # Memoized per process (config is frozen at boot; Config.reload! in dev
        # clears Config, so we re-derive lazily on next access).
        def segment_roles
          @segment_roles ||= begin
            segs = Pito::Chat::Segments.for(verb: :analyze, entity: :channel)
            segs.each_with_object({}) { |s, h| h[s.name] = s.kind.to_s }
          end
        end

        # The pending analyze events ({kind:, payload:}) for one scope — a `:system`
        # card, an `:enhanced` card, or both, per `roles:`. Used by the chat handler
        # AND the glance→new-pair follow-up handler so both build identical messages.
        # `roles:` defaults to BOTH so every existing caller is unaffected; the
        # analyze handler narrows it from the parsed segment selection (plan-0.9.5
        # D3: bare `analyze` → numbers only; `full` → both).
        # The :enhanced message is ALWAYS lifetime (owner 2026-06-29) — its
        # audience-composition bars + retention are lifetime, so the whole card
        # ignores shift+space. This also makes it cacheable with a 1-day TTL (0.9.0).
        # The :system card keeps the shift+space period.
        ENHANCED_PERIOD = "lifetime"

        def pair(level:, entity_ids:, title:, period:, conversation:, selection: nil, roles: ROLES)
          roles.map do |role|
            role_period = role == "enhanced" ? ENHANCED_PERIOD : period
            {
              kind:    ROLE_KINDS.fetch(role),
              payload: pending(role:, title:, level:, entity_ids:, period: role_period, conversation:, selection:)
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
          role     = marker["role"].to_sym
          level    = marker["level"].to_sym
          scaffold = data[:scaffold] || {}
          charts   = data[:charts] || {}
          bars     = (data[:bars] || {}).transform_keys(&:to_sym)
          selection = Pito::Analytics::MetricSelection.from_lists(marker["with"], marker["without"])

          chart_captions = charts.each_with_object({}) do |(metric, chart), h|
            h[metric] = chart && render_chart_caption(metric:, chart:)
          end
          bar_captions = bars.each_with_object({}) { |(metric, _rows), h| h[metric] = render_bar_caption(metric) }

          likes   = likes_marker(data[:likes])
          cells   = cells_for(role:, level:, scaffold:, selection:, charts:, chart_captions:, bars:, bar_captions:, likes:)
          analyze = marker.merge("status" => "ready", "scaffold" => stringify_scaffold(scaffold))

          # Persist each chart (with its sampled caption) so a mutate reply
          # can re-render the chart without re-fetching from YouTube.
          charts.each do |metric, chart|
            analyze[metric.to_s] = chart.merge("caption" => chart_captions[metric]) if chart
          end
          # Persist the bar breakdowns (+ captions) so a mutate reply re-renders
          # without refetch (string-keyed rows for jsonb).
          analyze["bars"]         = stringify_bars(bars) if bars.present?
          analyze["bar_captions"] = bar_captions.transform_keys(&:to_s).transform_values(&:to_s) if bar_captions.present?
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
          role      = marker["role"].to_sym
          level     = marker["level"].to_sym
          scaffold  = symbolize_scaffold(marker["scaffold"])
          selection = Pito::Analytics::MetricSelection.from_lists(with, without)

          # Read charts from the persisted marker (string-keyed; captions included).
          charts = CHART_METRIC_KEYS.each_with_object({}) do |key, h|
            h[key.to_sym] = marker[key] if marker[key].present?
          end
          chart_captions = charts.transform_values { |chart| chart&.fetch("caption", nil) }

          # Read bar breakdowns + captions from the persisted marker (string-keyed).
          bars         = (marker["bars"] || {}).transform_keys(&:to_sym)
          bar_captions = (marker["bar_captions"] || {}).transform_keys(&:to_sym)

          cells   = cells_for(role:, level:, scaffold:, selection:, charts:, chart_captions:, bars:, bar_captions:, likes: marker["likes"])
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
        def cells_for(role:, level:, scaffold:, selection:, charts: {}, chart_captions: {}, bars: {}, bar_captions: {}, likes: nil)
          metrics = Pito::Analytics::MetricOrder.for(role: role.to_sym, level: level.to_sym)
          metrics = Pito::Analytics::MetricSelection.apply(metrics, selection)
          metrics.map do |metric|
            chart = charts[metric]
            if metric == :likes && likes_hearts?(likes)
              heart_cell(likes)
            elsif metric == :day_of_week_heatmap && chart.present?
              { heatmap: metric, values: Array(chart["values"]), caption: chart_captions[metric] }
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
            elsif bars[metric].present?
              bar_cell(metric, bars[metric], bar_captions[metric])
            elsif NO_DATA_METRICS.include?(metric)
              no_data_cell(metric)
            else
              {
                label: Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(metric)),
                value: scaffold_pulled?(scaffold, metric) ? "1" : "0"
              }
            end
          end
        end

        # A would-be Area/Heart/Bar metric with no data → the NoData placeholder
        # cell. The metric label rides along as the (identifying) caption; the
        # canvas itself is blank for now (content TBD by owner).
        def no_data_cell(metric)
          { no_data: true, caption: Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(metric)) }
        end

        # Build a BarChart cell from a metric's Breakdown rows ([{key,pct}], string-
        # or symbol-keyed). Maps each share to the component's {label, color, pct,
        # value_label} via the per-metric presentation config; presentation runs at
        # render time so a re-render picks up current copy/translations.
        def bar_cell(metric, rows, caption)
          built  = Array(rows).each_with_index.map do |row, i|
            key = (row[:key] || row["key"]).to_s
            pct = (row[:pct] || row["pct"]).to_f
            pres = bar_presentation(metric, key, i)
            { label: pres[:label], color: pres[:color], pct:, value_label: format("%.1f%%", pct) }
          end
          { bars: built, caption: }
        end

        # Per-metric presentation for one breakdown share → { label:, color: }.
        # Categorical metrics map by KEY (BAR_COLORS); geography/age colour by ORDER
        # from a ramp and derive labels (country code as-is / "age25-34" → "25–34").
        def bar_presentation(metric, key, index)
          case metric
          when :subscribed_status
            sub = key == "SUBSCRIBED"
            { label: Pito::Copy.render("pito.copy.analytics.bars.subscribed_status.#{sub ? 'subscribed' : 'unsubscribed'}"),
              color: BAR_COLORS[:subscribed_status].fetch(key, :red) }
          when :devices
            slug = { "MOBILE" => "mobile", "DESKTOP" => "computer", "TV" => "tv" }.fetch(key, "mobile")
            { label: Pito::Copy.render("pito.copy.analytics.bars.devices.#{slug}"),
              color: BAR_COLORS[:devices].fetch(key, :blue) }
          when :demographics_gender
            g    = %w[male female gender_other].include?(key) ? key : "gender_other"
            slug = { "male" => "male", "female" => "female", "gender_other" => "other" }.fetch(g)
            { label: Pito::Copy.render("pito.copy.analytics.bars.gender.#{slug}"),
              color: BAR_COLORS[:demographics_gender].fetch(g, :purple) }
          when :geography
            { label: other_key?(key) ? other_label : Pito::Geo.country_name(key),
              color: GEO_RAMP[index % GEO_RAMP.size] }
          when :demographics_age
            { label: other_key?(key) ? other_label : format_age(key),
              color: AGE_RAMP[index % AGE_RAMP.size] }
          else
            { label: key, color: :blue }
          end
        end

        # G78: the Breakdown rollup bucket — the 5th bar summing the long tail
        # so charts total 100. Only ramp metrics (geography/age) can carry it.
        def other_key?(key)
          key == Pito::Analytics::Breakdown::OTHER_KEY
        end

        def other_label
          Pito::Copy.render("pito.copy.analytics.bars.other")
        end

        # "age25-34" → "25–34"; "age65-" → "65+"; strips the "age" prefix.
        def format_age(key)
          s = key.to_s.sub(/\Aage/, "")
          s.end_with?("-") ? "#{s.chomp('-')}+" : s.tr("-", "–")
        end

        # Subject noun (shimmered blue→purple) for each bar metric's caption.
        BAR_CAPTION_SUBJECT = {
          subscribed_status:   "Subscribers",
          devices:             "Devices",
          geography:           "Geography",
          demographics_gender: "Gender",
          demographics_age:    "Age"
        }.freeze

        # Per-metric bar caption — a 50-variant witty line in the house voice, with
        # the metric noun as the shimmered SUBJECT and a cyan "lifetime" REFERENCE
        # token (these bars are lifetime). Mirrors render_chart_caption /
        # render_likes_caption: html-safe, persisted in the marker, re-rendered raw.
        def render_bar_caption(metric)
          Pito::Copy.render_html(
            "pito.copy.analytics.bars.caption.#{metric}",
            { subject:   BAR_CAPTION_SUBJECT.fetch(metric, metric.to_s),
              reference: Pito::Shimmer::TokenComponent.html("lifetime") },
            shimmer: [ :subject ]
          )
        end

        # Stringify Breakdown rows for jsonb persistence: { metric => [{ "key","pct" }] }.
        def stringify_bars(bars)
          bars.each_with_object({}) do |(metric, rows), h|
            h[metric.to_s] = Array(rows).map { |r| { "key" => (r[:key] || r["key"]).to_s, "pct" => (r[:pct] || r["pct"]).to_f } }
          end
        end

        # The persisted likes marker carries hearts? `likes` is the string-keyed
        # `{ "hearts" => [...], "caption" => html }` hash (or nil).
        def likes_hearts?(likes)
          likes.is_a?(Hash) && Array(likes["hearts"]).any?
        end

        # Build the HEART grid cell from the persisted likes marker — symbolises the
        # stored colour + keys for Pito::Analytics::Visualizers::Heart.
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
          return render_retention_caption(chart:) if metric == :retention
          return render_heatmap_caption(values: chart["values"] || chart[:values]) if metric == :day_of_week_heatmap

          caption = Pito::Copy.render_html(
            "pito.copy.analyze.metric_caption",
            {
              metric: Pito::Copy.render(Pito::Analytics::MetricOrder.label_key(metric)),
              value:  chart_value_html(metric:, chart:)
            },
            shimmer: [ :metric ]
          )

          caption
        end

        # Retention's OWN witty/ironic caption (distinct from the generic chart
        # caption) — the mean retention %% as a cyan SUBJECT token + the benchmark
        # word in its trend colour. 50-variant pool. html-safe; persisted + re-rendered raw.
        def render_retention_caption(chart:)
          pct       = (chart["total_pct"] || chart[:total_pct]).to_f
          benchmark = chart["benchmark_word"] || chart[:benchmark_word] || "typical"
          Pito::Copy.render_html(
            "pito.copy.analyze.retention_caption",
            { value: "#{pct.round}%", benchmark: benchmark_word_html(benchmark) },
            shimmer: [ :value ]
          )
        end

        # Full weekday names (Mon..Sun) parallel to WeekdaySeries#values, for the
        # heatmap caption's "best day" subject.
        DAY_NAMES = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze

        # The day-of-week heatmap's witty caption — names the BUSIEST weekday (the
        # green bar) as the blue→purple SUBJECT token, from the 50-variant pool.
        # html-safe; persisted in the marker and re-rendered raw.
        def render_heatmap_caption(values:)
          vals   = Array(values).map(&:to_f)
          best_i = (0...vals.size).max_by { |i| vals[i] } || 0
          Pito::Copy.render_html(
            "pito.copy.analyze.day_of_week_caption",
            { day: DAY_NAMES[best_i] || DAY_NAMES.first },
            shimmer: [ :day ]
          )
        end

        # The witty caption under the likes-hearts (Pito::Analytics::Visualizers::Heart) — the
        # SUBJECT ("Likes vs Dislikes", blue→purple shimmer) + the score% as a cyan
        # token followed by the cyan "lifetime" reference. Mirrors
        # render_chart_caption's render_html/shimmer path; html-safe; persisted in
        # the marker and re-rendered raw. Shared by the analyze grid (LIKES3), the
        # demo, and the isolation preview so the caption is never hand-tuned.
        #
        # @param score [Numeric] 0..100 likes-vs-dislikes %
        # @param label [String]  the subject label (default "Likes vs Dislikes")
        def render_likes_caption(score:, label: "Likes vs Dislikes")
          pct   = format("%.2f%%", score.to_f.clamp(0.0, 100.0))
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
            Pito::Analytics::Support::TrendTriangle.html(
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
          case metric
          when :watched_hours
            "#{chart["total"].to_f.round}h"
          when :subs
            v = chart["total"].to_i
            v.negative? ? "-#{Pito::Formatter::CompactCount.call(v.abs)}" : Pito::Formatter::CompactCount.call(v)
          when :avg_view_duration
            Pito::Formatter::Duration.call(chart["total"].to_f) || "0:00"
          when :avg_viewed_pct
            # PULLED from YouTube's averageViewPercentage (views-weighted) — just the
            # percentage; no paired M:SS (owner: don't derive; avg_view_duration is
            # its own metric). total_pct is the views-weighted overall %.
            format("%.1f%%", chart["total_pct"].to_f)
          else
            Pito::Formatter::CompactCount.call(chart["total"].to_i)
          end
        end

        def marker(status, role:, title:, level:, entity_ids:, period:, intro:, selection: nil, token: nil, metric_keys: nil)
          {
            "status"      => status,
            "role"        => role.to_s,
            "title"       => title,
            "level"       => level.to_s,
            "entity_ids"  => Array(entity_ids),
            "period"      => period,
            "intro"       => intro,
            "with"        => Array(selection&.with).map(&:to_s),
            "without"     => Array(selection&.without).map(&:to_s),
            # Progressive fan-out: the per-message dom-id token + the ordered metric
            # keys the fan-out enqueues a job for. nil for non-fanned callers.
            "token"       => token,
            "metric_keys" => metric_keys
          }.compact
        end
      end
    end
  end
end
