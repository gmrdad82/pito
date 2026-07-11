# frozen_string_literal: true

require "fileutils"
require "json"

module Pito
  module Bench
    # READONLY benchmark runner — backs `rake pito:bench`.
    #
    # Every step runs under two mechanical guarantees:
    #
    #   * network  — NetworkGuard.while_blocked: any outbound TCP/HTTP attempt
    #     raises, so a "read" path that would secretly refetch shows up as a
    #     step error instead of a network call.
    #   * app data — the primary AR connection is switched to a read-only
    #     session (`SET default_transaction_read_only = ON`) for the run, so
    #     any accidental INSERT/UPDATE/DELETE raises. SolidCache uses its own
    #     connection pool (own database in production) and stays writable —
    #     cache writes are derived data, not app data.
    #
    # Steps are classes exposing `label` (String) and `call(ctx) → Hash` (their
    # metrics; flat key => scalar). Each step is timed on the monotonic clock
    # and rescued individually — one failing step reports its error and the
    # run continues.
    #
    # Output: an aligned table on `io` + a JSON snapshot under `tmp/bench/`
    # (`bench-<utc-ts>.json`) so runs diff cleanly across the release's phases.
    #
    #   Pito::Bench::Runner.call                          # all steps, defaults
    #   Pito::Bench::Runner.call(uuid: "…", iterations: 100)
    #
    # `uuid` scopes the replay step to a specific conversation (default: the
    # one with the most events); `iterations` drives the microbench loops.
    class Runner
      STEPS = [
        Steps::Replay,
        Steps::Components,
        Steps::Copy,
        Steps::Folds,
        Steps::Inventory,
        Steps::ColdPaths
      ].freeze

      Ctx = Data.define(:uuid, :iterations)

      def self.call(...) = new(...).call

      def initialize(uuid: nil, iterations: 50, io: $stdout, root: Rails.root, steps: STEPS)
        @ctx   = Ctx.new(uuid:, iterations:)
        @io    = io
        @root  = root
        @steps = steps
      end

      # @return [Hash] { steps: [result Hash, …], snapshot: Pathname }
      def call
        results = with_memory_cache do
          read_only_session do
            NetworkGuard.while_blocked { @steps.map { |step| run_step(step) } }
          end
        end

        print_table(results)
        snapshot = write_snapshot(results)
        @io.puts("snapshot: #{snapshot}")
        { steps: results, snapshot: snapshot }
      end

      private

      # ── guarantees ────────────────────────────────────────────────────────

      # The render paths WRITE to Rails.cache by design (L1 fragments, L2
      # snapshots — 0.9.0), and SolidCache rides the read-only DB session.
      # Swapping in a MemoryStore keeps READONLY absolute (zero DB writes,
      # derived or not) while the cache layer stays functional — so replay
      # timings measure the real cached-serving path.
      def with_memory_cache
        original    = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        yield
      ensure
        Rails.cache = original
      end

      # Read-only session on the primary connection; always reset on exit so
      # the connection returns to the pool writable.
      def read_only_session
        conn = ActiveRecord::Base.connection
        conn.execute("SET default_transaction_read_only = ON")
        yield
      ensure
        conn.execute("SET default_transaction_read_only = OFF")
      end

      # ── execution ─────────────────────────────────────────────────────────

      def run_step(step)
        t0      = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        metrics = step.call(@ctx)
        { "step" => step.label, "ms" => elapsed_ms(t0), "metrics" => metrics, "error" => nil }
      rescue StandardError => e
        { "step" => step.label, "ms" => elapsed_ms(t0), "metrics" => {}, "error" => "#{e.class}: #{e.message}" }
      end

      def elapsed_ms(t0)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(2)
      end

      # ── output ────────────────────────────────────────────────────────────

      def print_table(results)
        @io.puts("pito:bench — #{Rails.env} · #{Time.current.utc.iso8601} · iterations=#{@ctx.iterations}")
        return @io.puts("(no steps registered yet)") if results.empty?

        width = results.map { |r| r["step"].length }.max
        results.each do |r|
          status = r["error"] ? "ERROR #{r['error']}" : format_metrics(r["metrics"])
          @io.puts(format("%-#{width}s  %10.2fms  %s", r["step"], r["ms"], status))
        end
      end

      def format_metrics(metrics)
        metrics.map { |k, v| "#{k}=#{v}" }.join("  ")
      end

      def write_snapshot(results)
        dir = @root.join("tmp/bench")
        FileUtils.mkdir_p(dir)
        path = dir.join("bench-#{Time.current.utc.strftime('%Y%m%d-%H%M%S')}.json")
        path.write(JSON.pretty_generate(snapshot_payload(results)))
        path
      end

      def snapshot_payload(results)
        {
          captured_at: Time.current.utc.iso8601,
          env:         Rails.env,
          version:     Pito::Version.suffix,
          uuid:        @ctx.uuid,
          iterations:  @ctx.iterations,
          steps:       results
        }
      end
    end
  end
end
