# frozen_string_literal: true

module Pito
  module Bench
    module Steps
      # Pito::Copy microbench — settles the "should Copy be cached?" question
      # with numbers. Three representative paths, each timed in µs per call:
      #
      #   plain    — bare key, no vars (pure I18n lookup + sample)
      #   vars     — key + %{title} interpolation (the common builder path)
      #   html     — render_html with a shimmer subject span (the costliest path)
      #
      # Runs ctx.iterations × 100 loops per path (µs-scale needs volume for a
      # stable average).
      module Copy
        # Real hot keys — both exist and are exercised on every glance/error.
        PLAIN_KEY = "pito.copy.errors.dispatch_failed"
        VARS_KEY  = "pito.copy.analytics.intro"

        module_function

        def label = "copy"

        # @param ctx [Pito::Bench::Runner::Ctx]
        # @return [Hash] avg µs per path
        def call(ctx)
          n = [ ctx.iterations, 1 ].max * 100
          {
            "plain_avg_us" => avg_us(n) { Pito::Copy.render(PLAIN_KEY) },
            "vars_avg_us"  => avg_us(n) { Pito::Copy.render(VARS_KEY, title: "Bench Title") },
            "html_avg_us"  => avg_us(n) { Pito::Copy.render_html(VARS_KEY, { title: "Bench Title" }, shimmer: [ :title ]) },
            "loops"        => n
          }
        end

        def avg_us(n)
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          n.times { yield }
          (((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000_000) / n).round(2)
        end
      end
    end
  end
end
