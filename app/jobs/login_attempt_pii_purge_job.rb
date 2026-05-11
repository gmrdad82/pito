# P25 follow-up — F6. PII retention sweep for `LoginAttempt` rows.
#
# Why: `LoginAttempt` carries `email_attempted` (the raw email the
# typist provided) on failed / invalid-password rows. Forensic value
# decays fast — after 90 days the operator's threat-investigation
# window is closed, but the row still carries an email tied to an
# (often correct) IP / fingerprint pair. That is PII we don't need to
# keep.
#
# Scope: this job ONLY purges `email_attempted` rows on:
#
#   - `result` in (`failed`)
#   - `reason` in (`wrong_password`, `unknown_account`)
#
# Rationale for the narrow scope:
#
#   - `success` rows attach to a known user — no PII purge needed; the
#     user already trusts us with their email.
#   - `pending_approval` / `blocked` / `rate_limited` rows carry
#     forensic value beyond the 90-day window (block lists, account
#     takeover investigations, audit trail).
#   - `twofa_failed` / `new_location_*` / `approved_*` / `blocked_*`
#     rows attach to an authenticated user — the email is not PII the
#     user did not already share.
#
# So we ONLY scrub the cheap-attack failed / invalid-password rows
# (which is also where attackers spray the typist's emails).
#
# Sweep semantics: rows older than 90 days have their
# `email_attempted` set to NULL (not the whole row — the IP /
# fingerprint / geo audit trail stays). `delete_all` would lose the
# block-list inputs.
#
# Sidekiq cron: `0 4 * * *` (daily 04:00 UTC) — same family of cron
# entries as `notification_cleanup` (03:30) and the analytics nightly
# sweep (04:00). Co-locating these reduces operator surprise.
class LoginAttemptPiiPurgeJob < ApplicationJob
  queue_as :default

  RETENTION_PERIOD = 90.days
  BATCH_SIZE       = 1_000

  # `result` + `reason` combinations whose `email_attempted` is purged.
  # Stored as enum integer pairs so the DB query is cheap and explicit.
  PURGE_RESULTS = %i[failed].freeze
  PURGE_REASONS = %i[wrong_password unknown_account].freeze

  def perform
    cutoff = RETENTION_PERIOD.ago
    result_ints = PURGE_RESULTS.map { |k| LoginAttempt.results[k] }
    reason_ints = PURGE_REASONS.map { |k| LoginAttempt.reasons[k] }

    total_purged = 0

    loop do
      batch_ids = LoginAttempt
        .where(result: result_ints, reason: reason_ints)
        .where.not(email_attempted: nil)
        .where(arel_table_created_at_lt(cutoff))
        .limit(BATCH_SIZE)
        .pluck(:id)

      break if batch_ids.empty?

      begin
        affected = LoginAttempt
          .where(id: batch_ids)
          .update_all(email_attempted: nil)
        total_purged += affected
      rescue StandardError => e
        # Defensive: a transient DB hiccup should NOT silently terminate
        # the sweep. Log + break so the next cron tick retries cleanly.
        Rails.logger.warn(
          "[LoginAttemptPiiPurgeJob] batch failed (#{e.class}: #{e.message}); " \
          "stopping this run. total_purged_so_far=#{total_purged}"
        )
        break
      end

      # Defensive: if the batch returned fewer rows than the limit
      # we've exhausted the candidate set; bail rather than loop again.
      break if batch_ids.length < BATCH_SIZE
    end

    Rails.logger.info(
      "[LoginAttemptPiiPurgeJob] scrubbed email_attempted on #{total_purged} " \
      "LoginAttempt row#{'s' if total_purged != 1} older than #{RETENTION_PERIOD.inspect}"
    )
    total_purged
  end

  private

  def arel_table_created_at_lt(cutoff)
    LoginAttempt.arel_table[:created_at].lt(cutoff)
  end
end
