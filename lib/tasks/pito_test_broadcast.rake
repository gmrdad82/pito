# FB-test-infra (2026-05-22). Dev/test rake tasks for exercising
# cable-driven ViewComponents (Sidekiq stats cell, Notifications
# indicator) without waiting for real Sidekiq activity or external
# events. Two surfaces:
#
#   `pito:test:broadcast_*` — synthesize a cable envelope on the
#     `pito:status_bar` channel with an arbitrary `kind:` + `payload:`.
#     Useful when you want to see the VC react to a specific state
#     (e.g. retry_count=42) without recreating the underlying world.
#
#   `pito:test:enqueue_*_job` — drop one of the three `Pito::Test::*`
#     dummy Sidekiq jobs into Redis so the real Sidekiq middleware
#     fires its own broadcast against the canonical envelope (full
#     stack exercise: enqueue -> middleware -> cable -> VC).
#
# 2026-05-22 (cable routing refactor): the `broadcast_sync` task was
# dropped — sync state is no longer externally settable. The sync
# indicator now pulses on ANY cable activity (`tui:cable-activity`
# event fanned out by `tui-status-bar` on every received message) and
# returns to `synced` after 400ms of quiet. Cable disconnection is
# the only path that flips the indicator to `disconnected`.
namespace :pito do
  namespace :test do
    desc "broadcast a synthetic sidekiq stats payload (busy, enqueued, retry_count)"
    task :broadcast_sidekiq, [ :busy, :enqueued, :retry_count ] => :environment do |_, args|
      payload = {
        busy: (args[:busy] || 0).to_i,
        enqueued: (args[:enqueued] || 0).to_i,
        retry: (args[:retry_count] || 0).to_i
      }
      Pito::CableBroadcaster.broadcast_status_bar(payload, kind: :sidekiq)
      puts "broadcasted sidekiq b=#{payload[:busy]} e=#{payload[:enqueued]} r=#{payload[:retry]}"
    end

    desc "broadcast a synthetic notifications payload (future_count)"
    task :broadcast_notifications, [ :future_count ] => :environment do |_, args|
      future_count = (args[:future_count] || 0).to_i
      Pito::CableBroadcaster.broadcast_status_bar(
        { future_count: future_count },
        kind: :notifications
      )
      puts "broadcasted notifications future_count=#{future_count}"
    end

    desc "enqueue a long-running dummy job (seconds, default 5) to populate Sidekiq busy queue"
    task :enqueue_sleep_job, [ :seconds ] => :environment do |_, args|
      seconds = (args[:seconds] || 5).to_i
      jid = Pito::Test::SleepJob.perform_async(seconds)
      puts "enqueued SleepJob jid=#{jid} sleep=#{seconds}s"
    end

    desc "enqueue a guaranteed-failing dummy job to populate Sidekiq retry queue"
    task enqueue_failing_job: :environment do
      jid = Pito::Test::FailingJob.perform_async
      puts "enqueued FailingJob jid=#{jid}"
    end

    desc "schedule a dummy job far in the future (seconds_from_now, default 3600) to populate Sidekiq scheduled set"
    task :enqueue_scheduled_job, [ :seconds_from_now ] => :environment do |_, args|
      seconds = (args[:seconds_from_now] || 3600).to_i
      jid = Pito::Test::ScheduledJob.perform_in(seconds.seconds)
      puts "scheduled ScheduledJob jid=#{jid} fire_in=#{seconds}s"
    end
  end
end
