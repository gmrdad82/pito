# Phase 25 — 01a (LD-4). MaxMind GeoLite2 offline lookup.
#
# Synchronous primary with async Sidekiq fallback. The auth path NEVER
# makes an outbound HTTP call — the lookup hits a local on-disk DB or
# bails out. WebMock is configured to disable net connect; this enricher
# stays inside that contract.
#
# Configuration:
#
#   - `ENV["PITO_GEOIP_DB_PATH"]` points at the GeoLite2 City `.mmdb`
#     file. `bin/setup` documents the download.
#   - If the file is missing OR the `MaxMind::DB` gem isn't loaded
#     (it's optional in this phase — only added once the user opts
#     into GeoIP), the enricher returns an empty hash and sets a
#     thread-local flag the logger reads to enqueue the backfill job.
#
# Output shape: `{city:, region:, country:}`. Keys are always present
# (nil on miss) so downstream callers can `merge`/`slice` without
# branching on a hash with fewer keys.
#
# Timing budget: a soft 5 ms cap (LD-4). The clock-watch happens here,
# not in the controller; over budget we abandon the lookup result and
# flip the same async flag so the row is backfilled by the job.
module Auth
  class GeoEnricher
    EMPTY = { city: nil, region: nil, country: nil }.freeze
    DEFERRED_THREAD_KEY = :pito_geo_enricher_deferred
    MAX_LOOKUP_MS = 5.0
    ENV_DB_PATH = "PITO_GEOIP_DB_PATH".freeze

    # Returns `{city:, region:, country:}`. Side-effect: sets
    # `Thread.current[:pito_geo_enricher_deferred] = true` when the
    # lookup misses or times out so the caller can enqueue the
    # async backfill.
    def self.call(ip)
      Thread.current[DEFERRED_THREAD_KEY] = false
      return EMPTY.dup if ip.nil?

      unless db_available?
        defer!("geo db unavailable")
        return EMPTY.dup
      end

      started_ms = monotonic_ms
      record = lookup(ip.to_s)
      elapsed = monotonic_ms - started_ms

      if elapsed > MAX_LOOKUP_MS
        defer!("geo lookup over budget (#{elapsed.round(2)} ms)")
        # Still return what we got — the row is logged, just maybe stale.
      end

      if record.nil? || record.empty?
        # Unknown IP — DON'T defer (the job would also miss). The row
        # writes with empty geo and the UI renders "location unknown".
        return EMPTY.dup
      end

      record
    rescue StandardError => e
      Rails.logger.warn("[Auth::GeoEnricher] lookup failed: #{e.class}: #{e.message}")
      defer!(e.message)
      EMPTY.dup
    end

    # Whether the most-recent call asked for an async backfill. The
    # controller reads this immediately after the call and clears it
    # by reading.
    def self.deferred?
      Thread.current[DEFERRED_THREAD_KEY] == true
    end

    def self.reset_deferred!
      Thread.current[DEFERRED_THREAD_KEY] = false
    end

    def self.defer!(reason)
      Thread.current[DEFERRED_THREAD_KEY] = true
      Rails.logger.info("[Auth::GeoEnricher] deferring backfill: #{reason}")
    end

    def self.db_available?
      return false unless defined?(MaxMind::DB)
      path = db_path
      path.present? && File.exist?(path)
    end

    def self.db_path
      ENV[ENV_DB_PATH].to_s
    end

    def self.monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    end

    # Hot path. Pulled into its own method so specs can stub the
    # MaxMind reader cleanly. Reader is memoized per-DB-path so the
    # `.mmdb` file is mmap'd once per process.
    def self.lookup(ip)
      data = reader.get(ip)
      return EMPTY.dup if data.nil?

      city_name    = data.dig("city", "names", "en")
      region_name  = (data["subdivisions"] || []).dig(0, "names", "en")
      country_code = data.dig("country", "iso_code")

      {
        city:    city_name,
        region:  region_name,
        country: country_code
      }
    end

    @reader = nil
    @reader_path = nil

    def self.reader
      path = db_path
      if @reader.nil? || @reader_path != path
        @reader = MaxMind::DB.new(path, mode: MaxMind::DB::MODE_MEMORY)
        @reader_path = path
      end
      @reader
    end

    # Test hook — drop the memoized reader so a spec can stub a
    # different fixture path between examples.
    def self.reset_reader_for_test!
      @reader = nil
      @reader_path = nil
    end
  end
end
