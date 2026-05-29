# pito:test:stack — dev/test rake surface for the stack panel's four
# sub-panels (Meilisearch / Voyage AI / PostgreSQL / Assets).
#
# Purpose:
#   All four stack sub-panels are ENTIRELY QUERY-TIME LIVE. Their data
#   originates from:
#     - Meilisearch: live API call to the search engine
#     - Voyage AI:   AppSetting probe + live embedding counts from the DB
#     - PostgreSQL:  live `pg_total_relation_size` + model `.count`
#     - Assets:      live filesystem stat on `Pito::AssetsRoot.root`
#
#   No persistent "test-mode flag" exists for any of the four, and none
#   was introduced here. This task is therefore a BROADCAST SIMULATOR
#   ONLY: it pushes synthetic cable envelopes on each sub-panel stream
#   so the live UI can be exercised without real service changes.
#   The live DB / filesystem data continues to be displayed after a page
#   refresh; the simulated broadcast only affects open browser sessions
#   that receive it over the ActionCable connection.
#
# Tasks:
#   bin/rails pito:test:stack:seed    # broadcast synthetic data for all 4 sub-panels
#   bin/rails pito:test:stack:reset   # broadcast a stack_reset event + restore live data
#
# Env vars (seed):
#   SUBPANEL=meilisearch|voyage|postgres|assets
#               scope broadcast to one sub-panel only (default: all four)
#   DELAY=ms    pause between sub-panel broadcasts in milliseconds (default: 300)
#
# Dependencies:
#   - Pito::CableBroadcaster (ActionCable + Redis must be reachable for
#     broadcasts to land; the task silently continues if Redis is down)
#
# Broadcast kinds used:
#   "stack_update" — synthetic data push; JS panel controller handles
#     this alongside normal "data" envelopes. A browser receiving this
#     while on the Home screen will re-paint the targeted sub-panel.
#   "stack_reset"  — signals the panel to fall back to live data (a
#     full-page reload is the simplest client-side behaviour; the JS
#     controller may treat this as a reload hint).

namespace :pito do
  namespace :test do
    namespace :stack do
      # Channel constants matching the CABLE_CHANNEL on each sub-panel VC.
      STACK_CHANNELS = {
        meilisearch: "pito:home:stack:meilisearch",
        voyage:      "pito:home:stack:voyage",
        postgres:    "pito:home:stack:postgres",
        assets:      "pito:home:stack:assets"
      }.freeze

      # ---------------------------------------------------------------------------
      # Synthetic payloads — realistic-looking numbers for each sub-panel.
      # These mirror the Hash shapes consumed by each sub-panel VC:
      #
      # Meilisearch: { healthy:, stats: { version: }, per_index_stats: [{ label:, documents:, size_bytes:, missing:, omit_size: }] }
      # Voyage:      { configured:, embed_rows: [{ label:, embedded: }], info: { model:, last_indexed:, hnsw_indexes:, last_24h: } }
      # PostgreSQL:  { status: { connected:, version: }, table_breakdown: [{ label:, count:, size_bytes: }] }
      # Assets:      { storage_status: { present:, writable:, size_bytes:, file_count: }, breakdown: [{ label:, file_count:, size_bytes: }] }
      # ---------------------------------------------------------------------------

      STACK_SEED_PAYLOADS = {
        meilisearch: {
          healthy: true,
          stats: { version: "1.10.3" },
          per_index_stats: [
            { label: "games",   documents: 2841, size_bytes: 18_456_320, missing: false },
            { label: "bundles", documents:  374, size_bytes: nil,        missing: false, omit_size: true }
          ]
        },
        voyage: {
          configured: true,
          embed_rows: [
            { label: "games",   embedded: 2841 },
            { label: "bundles", embedded:  374 }
          ],
          info: {
            model:          "voyage-3",
            last_indexed:   "2026-05-25T08:30:00Z",
            hnsw_indexes:   2,
            last_24h:       512
          }
        },
        postgres: {
          status:          { connected: true, adapter: "postgresql", database: "pito_development", version: "17" },
          table_breakdown: [
            { label: "games",   count: 2841, size_bytes: 74_710_016 },
            { label: "bundles", count:  374, size_bytes: 12_582_912 }
          ]
        },
        assets: {
          storage_status: {
            path:       "/srv/pito/assets",
            present:    true,
            writable:   true,
            size_bytes: 4_831_838_208,
            file_count: 9_312
          },
          breakdown: [
            { label: "cover arts",  file_count: 8_940, size_bytes: 4_612_440_064 },
            { label: "composites", file_count:   372, size_bytes:   219_398_144 }
          ]
        }
      }.freeze

      desc "broadcast synthetic stack data on all 4 sub-panel channels " \
           "(SUBPANEL=meilisearch|voyage|postgres|assets  DELAY=300)"
      task seed: :environment do
        subpanel_filter = ENV["SUBPANEL"].to_s.strip.downcase.presence
        delay_ms        = ENV.fetch("DELAY", 300).to_i.clamp(0, 30_000)

        targets = if subpanel_filter
          unless STACK_CHANNELS.key?(subpanel_filter.to_sym)
            abort "[pito:test:stack:seed] unknown SUBPANEL=#{subpanel_filter}; " \
                  "valid: #{STACK_CHANNELS.keys.join(', ')}"
          end
          { subpanel_filter.to_sym => STACK_CHANNELS[subpanel_filter.to_sym] }
        else
          STACK_CHANNELS
        end

        puts "[pito:test:stack:seed] broadcasting synthetic data on #{targets.keys.join(', ')} " \
             "sub-panel(s); delay=#{delay_ms}ms"
        puts "[pito:test:stack:seed] NOTE: all 4 sub-panels are query-time live. This task " \
             "is a broadcast simulator only; a page refresh will restore live data."

        targets.each_with_index do |(name, channel), idx|
          payload = STACK_SEED_PAYLOADS[name]

          begin
            Pito::CableBroadcaster.broadcast_panel(
              channel,
              kind:    "stack_update",
              payload: payload.merge(synthetic: true, seeded_at: Time.current.iso8601)
            )
            puts "[pito:test:stack:seed] #{name} -> #{channel} broadcast OK"
          rescue => e
            warn "[pito:test:stack:seed] #{name} broadcast FAILED: #{e.message}"
          end

          sleep(delay_ms / 1000.0) if delay_ms.positive? && idx < targets.size - 1
        end

        puts "[pito:test:stack:seed] done"
      end

      desc "broadcast stack_reset on all 4 sub-panel channels to signal live-data restore"
      task reset: :environment do
        puts "[pito:test:stack:reset] broadcasting stack_reset on all sub-panel channels"

        STACK_CHANNELS.each do |name, channel|
          begin
            Pito::CableBroadcaster.broadcast_panel(
              channel,
              kind:    "stack_reset",
              payload: { reset_at: Time.current.iso8601, synthetic: false }
            )
            puts "[pito:test:stack:reset] #{name} -> #{channel} reset OK"
          rescue => e
            warn "[pito:test:stack:reset] #{name} broadcast FAILED: #{e.message}"
          end
        end

        puts "[pito:test:stack:reset] done — clients should reload to restore live data"
      end
    end
  end
end
