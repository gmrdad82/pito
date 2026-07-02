# frozen_string_literal: true

module Pito
  module Bench
    module Steps
      # Component microbench — renders exemplar components N× (ctx.iterations)
      # from REAL stored payloads, reporting avg ms per render. Exemplars:
      #
      #   echo          — an echo event (replay's surprise hot spot; pins its cost)
      #   list_table    — a system event with structured table_rows (grid built per render)
      #   glance_card   — a ready `show X` analytics :enhanced event
      #   analyze_card  — a ready analyze event (body baked; measures chrome cost)
      #   share_event   — a shared event rendered as /share does (suppress_reply)
      #   area_chart    — Visualizers::Area from a ready analyze marker's views chart
      #                   (the braille compute the L0.5 cell cache will amortize)
      #
      # A missing exemplar reports "n/a" — the step never fails on sparse data.
      module Components
        module_function

        def label = "components"

        # @param ctx [Pito::Bench::Runner::Ctx]
        # @return [Hash] <exemplar>_avg_ms per found exemplar
        def call(ctx)
          n = [ ctx.iterations, 1 ].max
          {
            "echo_avg_ms"         => bench_event(echo_event, n),
            "list_table_avg_ms"   => bench_event(list_event, n),
            "glance_card_avg_ms"  => bench_event(glance_event, n),
            "analyze_card_avg_ms" => bench_event(analyze_event, n),
            "share_event_avg_ms"  => bench_share(n),
            "area_chart_avg_ms"   => bench_area(n)
          }
        end

        # ── exemplar lookups (newest first; nil when absent) ──────────────────

        def echo_event
          ::Event.where(kind: "echo").order(created_at: :desc).first
        end

        def list_event
          ::Event.where(kind: "system")
                 .where("jsonb_exists(payload, 'table_rows')")
                 .order(created_at: :desc).first
        end

        def glance_event
          ::Event.where(kind: "enhanced")
                 .where("payload->'analytics'->>'status' = 'ready'")
                 .order(created_at: :desc).first
        end

        def analyze_event
          ::Event.where("payload->'analyze'->>'status' = 'ready'")
                 .order(created_at: :desc).first
        end

        # ── benches ───────────────────────────────────────────────────────────

        def bench_event(event, n)
          return "n/a" if event.nil?

          avg_ms(n) { Pito::Stream::EventRenderer.render(event) }
        end

        # Renders the shared event the way /share/:uuid does — reply suppressed.
        def bench_share(n)
          event = ::Share.order(created_at: :desc).first&.event
          return "n/a" if event.nil?

          avg_ms(n) { Pito::Stream::EventRenderer.render_public(event) }
        end

        # The braille area-chart visualizer, fed a REAL persisted views chart
        # (ready analyze markers persist per-metric chart data for mutate replies).
        # Needs a :system-role card — :enhanced carries no views chart.
        def bench_area(n)
          chart = ::Event.where("payload->'analyze'->>'status' = 'ready'")
                         .where("jsonb_exists(payload->'analyze', 'views')")
                         .order(created_at: :desc).first
                         &.payload&.dig("analyze", "views")
          return "n/a" if chart.nil? || chart["series"].blank?

          avg_ms(n) do
            ApplicationController.renderer.render(
              Pito::Analytics::Visualizers::Area.new(
                metric:          :views,
                series:          chart["series"],
                target_daily:    chart["target_daily"].to_f,
                caption:         chart["caption"].to_s,
                trend:           chart.fetch("trend", true),
                reference_token: chart["reference_token"],
                dates:           chart["dates"]
              ),
              layout: false
            )
          end
        end

        def avg_ms(n)
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          n.times { yield }
          (((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000) / n).round(3)
        end
      end
    end
  end
end
