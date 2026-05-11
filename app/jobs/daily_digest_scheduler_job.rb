# Phase 26 — 01e. Daily digest scheduler — hourly cron tick.
#
# Fires every hour at minute 0 (`config/sidekiq_cron.yml` →
# `daily_digest_scheduler`). On each tick:
#
#   1. Resolve the install's "anchor" user — the user with the lowest
#      id. The anchor's `time_zone` decides when the install's 09:00
#      local fires; the anchor's `last_digest_run_at` carries the
#      install-level cooldown stamp.
#   2. Verify at least one `NotificationDeliveryChannel` has
#      `daily_digest = true`. The channels are install-level (no
#      per-user `user_id`, per ADR 0003), so a single configured
#      channel covers the whole install.
#   3. Compute the "most recent anchor-local 09:00" instant in UTC.
#      If that instant falls inside `(tick - 1h, tick]` AND the
#      anchor's `last_digest_run_at < tick - 23h`, atomically stamp
#      `last_digest_run_at` on the anchor and enqueue
#      `DailyDigestDeliverJob.perform_later(anchor.id)`.
#
# Install-level dispatch (P26 reviewer concern 1, locked decision):
# ONE digest per install per day, regardless of user count. The
# digest composer aggregates ALL users' activity install-wide
# (channels, videos, footage, login attempts, notifications); the
# deliver job POSTs once per enabled webhook. On a multi-user
# install, picking the anchor on the lowest-id user prevents N users
# from N-firing into the same Slack/Discord channel.
#
# Cross-user race (P26 reviewer concern 3): inherently addressed by
# the install-level dispatch. The cooldown stamp lives on a single
# row (the anchor); the atomic UPDATE...WHERE last_digest_run_at <
# guard prevents double-fire even if two cron ticks land in the
# same instant.
#
# DST handling:
#
#   - Spring-forward: if the anchor's local 09:00 falls inside the
#     "missing" hour, `ActiveSupport::TimeZone#local` resolves it to
#     the post-jump instant; the tick after the post-jump 09:00
#     fires.
#   - Fall-back: the local 09:00 happens once even though the
#     wallclock repeats earlier. `Time.zone.local` returns the first
#     occurrence; the `last_digest_run_at` guard prevents double-fire.
#
# Edge zones (anchor-tz based — pick a single illustrative table):
#
#   - UTC+14 (`Pacific/Kiritimati`) — local 09:00 in UTC is 19:00 the
#     PREVIOUS calendar day. The 19:00 UTC tick fires.
#   - UTC-11 (`Pacific/Pago_Pago`) — local 09:00 in UTC is 20:00 the
#     SAME calendar day. The 20:00 UTC tick fires.
#   - Asia/Kolkata (+5:30) — local 09:00 in UTC is 03:30 UTC. There
#     is no 03:30 UTC tick; the 1-hour pickup window means the
#     04:00 UTC tick fires (`03:30 ∈ (03:00, 04:00]`).
#   - Australia/Eucla (+8:45) — local 09:00 in UTC is 00:15 UTC. The
#     01:00 UTC tick fires.
#
# Idempotent: re-running the job inside the same hour does not
# double-fire because `last_digest_run_at` was stamped on the first
# pickup.
class DailyDigestSchedulerJob < ApplicationJob
  queue_as :default

  PICKUP_WINDOW = 1.hour
  COOLDOWN = 23.hours
  TARGET_LOCAL_HOUR = 9

  def perform
    tick = Time.current

    anchor = anchor_user
    return if anchor.nil?
    return unless any_digest_channel_configured?
    return unless ripe_for_pickup?(anchor, tick: tick)

    # Atomic claim. If two scheduler ticks race (manual run + cron
    # tick within the same instant), the second one's UPDATE
    # affects 0 rows because the `last_digest_run_at` guard
    # disqualifies the anchor.
    claimed = User
                .where(id: anchor.id)
                .where("last_digest_run_at < ?", tick - COOLDOWN)
                .update_all(last_digest_run_at: tick)

    return if claimed.zero?

    DailyDigestDeliverJob.perform_later(anchor.id)
  end

  private

  # Install-level anchor. The lowest-id user is the conventional
  # "primary owner" (first install seed). Their tz drives the 09:00
  # local fire-time; their `last_digest_run_at` carries the
  # install-wide cooldown stamp.
  def anchor_user
    User.order(:id).first
  end

  # True iff at least one `NotificationDeliveryChannel` is configured
  # for daily digest. Channels are install-level singletons keyed by
  # `kind` (per ADR 0003) so this is a single existence check, NOT a
  # per-user join.
  def any_digest_channel_configured?
    NotificationDeliveryChannel.where(daily_digest: true).exists?
  end

  # True iff the anchor's local 09:00 instant has passed within the
  # last `PICKUP_WINDOW` (1 hour) ending at `tick`, AND the cooldown
  # has elapsed.
  #
  # Cross-day handling: we compute 09:00 for today/yesterday/tomorrow
  # in the anchor's zone and check any of them. This covers edge
  # zones where the today-local-date at the UTC tick disagrees with
  # the anchor-local-date (e.g. UTC+14 at the 19:00 UTC tick — UTC
  # is on day N, anchor is on day N+1).
  def ripe_for_pickup?(anchor, tick:)
    return false unless anchor.last_digest_run_at < tick - COOLDOWN

    tz = anchor.tz
    local_now = tick.in_time_zone(tz)
    [ local_now.to_date, local_now.to_date - 1, local_now.to_date + 1 ].any? do |local_date|
      target_local = tz.local(local_date.year, local_date.month, local_date.day, TARGET_LOCAL_HOUR, 0, 0)
      target_utc = target_local.utc
      target_utc > (tick - PICKUP_WINDOW) && target_utc <= tick
    end
  rescue StandardError => e
    Rails.logger.warn(
      "DailyDigestSchedulerJob: ripe_for_pickup? failed for user##{anchor.id}: #{e.class}: #{e.message}"
    )
    false
  end
end
