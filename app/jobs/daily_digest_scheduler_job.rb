# Phase 26 — 01e. Daily digest scheduler — hourly cron tick.
#
# Fires every hour at minute 0 (`config/sidekiq_cron.yml` →
# `daily_digest_scheduler`). On each tick:
#
#   1. Enumerate users who have at least one
#      `NotificationDeliveryChannel` with `daily_digest = true`.
#   2. For each such user, compute the "most recent user-local 09:00"
#      instant in UTC using their stored `time_zone`.
#   3. If that instant has passed within the last hour
#      (`(tick - 1h, tick]`) AND
#      `last_digest_run_at < tick - 23.hours`, pick the user.
#   4. Stamp `last_digest_run_at = Time.current` (single UPDATE per
#      user) and enqueue `DailyDigestDeliverJob.perform_later(user.id)`.
#
# DST handling:
#
#   - Spring-forward: if a user's local 09:00 falls inside the "missing"
#     hour (rare — most spring-forward jumps are 02:00 → 03:00, but
#     some zones have other patterns), `ActiveSupport::TimeZone#local`
#     resolves it to the post-jump instant. The tick after the post-jump
#     09:00 picks the user.
#   - Fall-back: the local 09:00 happens once even though the wallclock
#     repeats earlier. `Time.zone.local` returns the first occurrence;
#     the `last_digest_run_at` guard prevents double-fire.
#
# Edge zones:
#
#   - UTC+14 (`Pacific/Kiritimati`) — local 09:00 in UTC is 19:00 the
#     PREVIOUS calendar day. The 19:00 UTC tick picks them.
#   - UTC-11 (`Pacific/Pago_Pago`) — local 09:00 in UTC is 20:00 the
#     SAME calendar day. The 20:00 UTC tick picks them.
#   - Asia/Kolkata (+5:30) — local 09:00 in UTC is 03:30 UTC. There is
#     no 03:30 UTC tick; the picker uses a 1-hour pickup window so the
#     04:00 UTC tick picks them (`03:30 ∈ (03:00, 04:00]`).
#   - Australia/Eucla (+8:45) — local 09:00 in UTC is 00:15 UTC. The
#     01:00 UTC tick picks them.
#
# Idempotent: re-running the job inside the same hour does not double-
# fire because `last_digest_run_at` was stamped on the first pickup.
class DailyDigestSchedulerJob < ApplicationJob
  queue_as :default

  PICKUP_WINDOW = 1.hour
  COOLDOWN = 23.hours
  TARGET_LOCAL_HOUR = 9

  def perform
    tick = Time.current
    pick_users(tick).find_each(batch_size: 500) do |user|
      next unless ripe_for_pickup?(user, tick: tick)

      # Atomic claim. If two scheduler ticks race (manual run + cron
      # tick within the same instant), the second one's UPDATE
      # affects 0 rows because the `last_digest_run_at` guard
      # disqualifies the user.
      claimed = User
                  .where(id: user.id)
                  .where("last_digest_run_at < ?", tick - COOLDOWN)
                  .update_all(last_digest_run_at: tick)

      next if claimed.zero?

      DailyDigestDeliverJob.perform_later(user.id)
    end
  end

  private

  # Users with at least one digest-enabled notification delivery
  # channel AND a cooldown that has elapsed. The cooldown filter at
  # the SQL layer is a fast pre-filter; the precise tz-aware check
  # runs in Ruby per-user.
  def pick_users(tick)
    User
      .where("last_digest_run_at < ?", tick - COOLDOWN)
      .where(
        "EXISTS (SELECT 1 FROM notification_delivery_channels c " \
        "WHERE c.daily_digest = true)"
      )
  end

  # True iff the user's local 09:00 instant has passed within the
  # last `PICKUP_WINDOW` (1 hour) ending at `tick`.
  #
  # Cross-day handling: we compute 09:00 for "today in the user's
  # zone" AND "yesterday in the user's zone" and check either. This
  # covers edge zones where the today-local-date at the UTC tick
  # disagrees with the user-local-date (e.g. UTC+14 at the 19:00 UTC
  # tick — UTC is on day N, user is on day N+1).
  def ripe_for_pickup?(user, tick:)
    tz = user.tz
    local_now = tick.in_time_zone(tz)
    [ local_now.to_date, local_now.to_date - 1, local_now.to_date + 1 ].any? do |local_date|
      target_local = tz.local(local_date.year, local_date.month, local_date.day, TARGET_LOCAL_HOUR, 0, 0)
      target_utc = target_local.utc
      target_utc > (tick - PICKUP_WINDOW) && target_utc <= tick
    end
  rescue StandardError => e
    Rails.logger.warn(
      "DailyDigestSchedulerJob: ripe_for_pickup? failed for user##{user.id}: #{e.class}: #{e.message}"
    )
    false
  end
end
