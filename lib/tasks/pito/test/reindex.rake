# pito:test:reindex — dev rake tasks for exercising reindex cable state
# without running an actual Meilisearch / Voyage AI indexing pass.
#
# Purpose: simulate the full `reindex_event` cable lifecycle (running →
# ticks → complete) so the Stack sub-panel UI state machine can be
# exercised offline, without burning Voyage API budget or waiting for a
# real job to finish.
#
# Tasks:
#   pito:test:reindex:simulate  — flip AppSetting.reindex_running? true,
#     broadcast `reindex_event` kind ticks for DURATION seconds (default
#     10), then flip back to false and broadcast `complete`. With
#     STUCK=yes the flag is left permanently true (no auto-reset); call
#     `pito:test:reindex:reset` to recover.
#
#   pito:test:reindex:reset     — force-clear AppSetting reindex lock for
#     both targets and broadcast a final `complete` event on both
#     channels. Safe to run even when no simulate is in flight.
#
# Env vars:
#   TARGET   — `meilisearch` (default) or `voyage`. Selects which
#              sub-panel channel receives the broadcasts. The companion
#              channel also receives its final `complete` broadcast on
#              reset so the UI never gets stuck.
#   DURATION — seconds to broadcast ticks before auto-completing.
#              Default 10. Ignored when STUCK=yes.
#   STUCK    — `yes` to leave reindex_running true indefinitely (tests
#              the paused/uncertain UI state). Default off.
#   DELAY    — milliseconds between tick broadcasts. Default 120
#              (matches the dot-loader animation cadence).
#
# Related:
#   AppSetting.start_reindex! / clear_reindex_lock! — DB flag contract
#   Pito::CableBroadcaster.broadcast_panel            — canonical envelope
#   Pito::Stack::MeilisearchSubPanelComponent         — cable channel source
#   Pito::Stack::VoyageSubPanelComponent              — cable channel source
#
namespace :pito do
  namespace :test do
    namespace :reindex do
      CHANNEL_MAP = {
        "meilisearch" => "pito:home:stack:meilisearch",
        "voyage"      => "pito:home:stack:voyage"
      }.freeze

      desc <<~DESC
        Simulate a reindex cable cycle (TARGET=meilisearch|voyage, DURATION=10, STUCK=yes, DELAY=120).
        Flips AppSetting.reindex_running? true, broadcasts reindex_event ticks, then clears (unless STUCK=yes).
      DESC
      task simulate: :environment do
        target   = (ENV.fetch("TARGET", "meilisearch")).downcase
        duration = (ENV.fetch("DURATION", "10")).to_i
        stuck    = ENV.fetch("STUCK", "no").downcase == "yes"
        delay_ms = (ENV.fetch("DELAY", "120")).to_i

        channel = CHANNEL_MAP[target]
        abort "Unknown TARGET '#{target}'. Use: #{CHANNEL_MAP.keys.join(' | ')}" unless channel

        puts "[pito:test:reindex:simulate] target=#{target} duration=#{duration}s stuck=#{stuck} delay=#{delay_ms}ms"
        puts "[pito:test:reindex:simulate] channel=#{channel}"

        # Flip the DB lock so the sub-panel renders its running state on
        # next page load / Turbo refresh.
        AppSetting.start_reindex!
        puts "[pito:test:reindex:simulate] AppSetting.reindex_running? = #{AppSetting.reindex_running?}"

        # Broadcast initial `running` event so live subscribers react
        # immediately without waiting for the first tick.
        Pito::CableBroadcaster.broadcast_panel(
          channel,
          kind: "reindex_event",
          payload: { state: "running" }
        )
        puts "[pito:test:reindex:simulate] broadcast running"

        if stuck
          puts "[pito:test:reindex:simulate] STUCK=yes — leaving reindex_running true. Run pito:test:reindex:reset to recover."
        else
          # Broadcast periodic ticks so any progress-sensitive subscriber
          # sees continuous activity. Uses the same `running` state on
          # each tick — the sub-panel ignores duplicate state transitions
          # gracefully.
          elapsed   = 0
          tick_secs = delay_ms / 1000.0

          while elapsed < duration
            sleep tick_secs
            elapsed += tick_secs
            Pito::CableBroadcaster.broadcast_panel(
              channel,
              kind: "reindex_event",
              payload: { state: "running", elapsed_ms: (elapsed * 1000).to_i }
            )
            print "."
            $stdout.flush
          end
          puts ""

          # Clear the DB flag and broadcast `complete` — mirrors exactly
          # what the real job's `ensure` block does.
          AppSetting.clear_reindex_lock!
          Pito::CableBroadcaster.broadcast_panel(
            channel,
            kind: "reindex_event",
            payload: { state: "complete" }
          )
          puts "[pito:test:reindex:simulate] done — AppSetting.reindex_running? = #{AppSetting.reindex_running?}"
        end
      end

      desc "Force-reset reindex lock for all targets (meilisearch + voyage) and broadcast complete."
      task reset: :environment do
        AppSetting.clear_reindex_lock!

        CHANNEL_MAP.each do |target, channel|
          Pito::CableBroadcaster.broadcast_panel(
            channel,
            kind: "reindex_event",
            payload: { state: "complete" }
          )
          puts "[pito:test:reindex:reset] broadcast complete on #{channel}"
        end

        puts "[pito:test:reindex:reset] AppSetting.reindex_running? = #{AppSetting.reindex_running?}"
      end
    end
  end
end
