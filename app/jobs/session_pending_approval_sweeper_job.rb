# Phase 25 — 01b. Sidekiq cron entry that runs every minute and
# transitions pending-approval sessions whose 10-minute window has
# elapsed. Delegates to `Auth::PendingSessionExpirer.call` — see that
# service for the audit-row contract and the idempotency notes.
#
# Schedule lives in `config/sidekiq_cron.yml`:
#
#     pending_session_approval_sweeper:
#       cron: "* * * * *"   # every minute
#       class: SessionPendingApprovalSweeperJob
#
# The 1-minute cadence is fine-grained — `approval_required_until` is
# in minutes, the sweep is cheap (indexed by state + expiry), and the
# state machine refuses retroactive approvals so a delayed sweep
# cannot let an expired row slip through.
class SessionPendingApprovalSweeperJob < ApplicationJob
  queue_as :default

  def perform
    transitioned = Auth::PendingSessionExpirer.call
    if transitioned.to_i.positive?
      Rails.logger.info(
        "[SessionPendingApprovalSweeperJob] transitioned=#{transitioned}"
      )
    end
    transitioned
  end
end
