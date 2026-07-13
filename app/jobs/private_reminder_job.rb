# frozen_string_literal: true

# Nightly "you have private vids sitting around" reminder — drives
# `Pito::Notifications::Source::PrivateReminder` end to end (P19/T19.2b).
#
# Counts PRIVATE, UNSCHEDULED videos (D2 — `Video.private_unscheduled`)
# uploaded more than a day ago. `published_at` is the column that honestly
# carries the upload time: `Pito::Sync::VideoLibrary#normalize_video` reads it
# straight off YouTube's `snippet.published_at`, which the API populates on
# upload regardless of privacy status. `publish_at`, by contrast, is the
# FUTURE-scheduled publish time the `private_unscheduled` scope itself already
# excludes — it is not an age signal. A fresh upload (<24h old) never counts,
# giving the owner a day to edit before being nagged.
#
# The source owns the dictionary line, the once-per-calendar-day dedupe, and
# the zero-count no-op (`report!` returns nil for both) — this job only
# drives it with the count. `Notification#after_create_commit` fans the
# message out to any configured Slack/Discord webhook automatically (see
# `NotificationWebhookDeliverJob`) — this job posts nothing to a webhook
# itself.
class PrivateReminderJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 1.day

  def perform
    count = Video.private_unscheduled.where("published_at < ?", STALE_AFTER.ago).count
    Pito::Notifications::Source::PrivateReminder.report!(count)
  end
end
