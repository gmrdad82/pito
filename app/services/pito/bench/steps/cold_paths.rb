# frozen_string_literal: true

module Pito
  module Bench
    module Steps
      # Dry cold-path counter — how many YouTube Analytics requests each hot
      # command WOULD fire, given the database's CURRENT primitive temperature
      # (warm rows short-circuit before the client, exactly as in production).
      # Runs the REAL fill code under Pito::Bench::DryRun (requests counted,
      # never fired; stores stubbed).
      #
      # Scenarios: `show` glance + `analyze` (:system and :enhanced roles) for
      # a vid, the most-linked game (the worst realistic fan-out), and a
      # channel. This is the number Phases 1–3 must collapse.
      module ColdPaths
        module_function

        def label = "cold_paths"

        # @param _ctx [Pito::Bench::Runner::Ctx]
        # @return [Hash] request counts per scenario
        def call(_ctx)
          video   = exemplar_video
          game    = exemplar_game
          channel = exemplar_channel

          metrics = {}
          metrics["show_vid_reqs"]     = video ? count_glance(video) : "n/a"
          metrics["show_game_reqs"]    = game ? count_glance(game) : "n/a"
          metrics["show_channel_reqs"] = channel ? count_glance(channel) : "n/a"

          { "vid" => video&.id, "game" => game&.id, "channel" => channel&.id }.each do |level, id|
            next metrics["analyze_#{level}_reqs"] = "n/a" if id.nil?

            first, repeat = count_analyze(level:, id:)
            metrics["analyze_#{level}_reqs"]        = first
            metrics["analyze_#{level}_repeat_reqs"] = repeat # MUST be 0 (warm reuse)
          end
          metrics["game_linked_vids"] = game ? game.linked_videos.count : 0
          metrics
        end

        # ── scenario counters ─────────────────────────────────────────────────

        # The glance fan-out: one MetricFill per glance metric (scalar + series
        # requests inside), exactly what AnalyticsFillJob dispatches.
        def count_glance(scope)
          keys = Pito::Analytics::ScalarsTableComponent::GLANCE_METRICS.map { |m| m[:key].to_s }
          DryRun.capture do
            keys.each { |key| Pito::Analytics::MetricFill.for(scope:, period: "28d", key:) }
          end["requests"]
        end

        # The analyze fan-out: one AnalyzeMetricFill per metric of BOTH roles
        # (:system on the shift+space period, :enhanced always lifetime) —
        # exactly what AnalyzePrepareJob dispatches for the pair. Runs the pair
        # TWICE inside one capture: the second pass folds from the first pass's
        # (virtual-)warm primitives, so its count is the repeat-analyze cost —
        # the 0.9.0 warm-reuse contract says it MUST be 0.
        def count_analyze(level:, id:)
          first = nil
          total = DryRun.capture do
            run_analyze_fills(level:, id:)
            first = DryRun.current_total
            run_analyze_fills(level:, id:)
          end["requests"]
          [ first, total - first ]
        end

        def run_analyze_fills(level:, id:)
          %w[system enhanced].each do |role|
            period = role == "enhanced" ? "lifetime" : "28d"
            Pito::Analytics::MetricOrder.for(role: role.to_sym, level: level.to_sym).each do |metric|
              Pito::Analytics::AnalyzeMetricFill.for(metric:, level:, entity_ids: [ id ], period:)
            end
          end
        end

        # ── exemplars (usable = connected, non-reauth channel) ────────────────

        def exemplar_video
          ::Video.where.not(youtube_video_id: nil)
                 .includes(:channel)
                 .order(created_at: :desc)
                 .limit(50)
                 .detect { |v| usable?(v.channel) }
        end

        # The game with the most linked vids — the worst realistic fan-out.
        def exemplar_game
          top_id = ::VideoGameLink.group(:game_id).count.max_by(&:last)&.first
          top_id && ::Game.find_by(id: top_id)
        end

        def exemplar_channel
          ::Channel.includes(:youtube_connection).detect { |c| usable?(c) }
        end

        def usable?(channel)
          conn = channel&.youtube_connection
          conn.present? && !conn.needs_reauth
        end
      end
    end
  end
end
