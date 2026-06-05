# frozen_string_literal: true

# No default seeds — content is bootstrapped from real data.
# Use `bin/rails pito:test:seeds:prepare` to snapshot current DB state,
# and `bin/rails pito:test:seeds:populate` to restore it.

# ── Sample notifications (idempotent) ──────────────────────────────────────────
#
# Creates 3 sample notifications for browser smoke testing. Guarded by message
# uniqueness so re-running `bin/rails db:seed` does not duplicate them.
[
  {
    message:    "Your video sync completed successfully.",
    read_at:    nil,
    created_at: 5.minutes.ago
  },
  {
    message:    "New channel milestone: 1 000 subscribers reached!",
    read_at:    nil,
    created_at: 3.hours.ago
  },
  {
    message:    "Weekly digest is ready for review.",
    read_at:    2.days.ago,
    created_at: 2.days.ago
  }
].each do |attrs|
  next if Notification.exists?(message: attrs[:message])

  Notification.create!(attrs.merge(updated_at: attrs[:created_at]))
end
