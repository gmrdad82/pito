# frozen_string_literal: true

# Adds an optional per-notification push title (`data.title` in the FCM
# payload — see Pito::Fcm::Sender). Nullable, no default, no backfill: old
# rows legitimately have no title (the Android client falls back to "PITO"
# client-side), and only sources with an obvious, copy-driven identity set
# one going forward (see Pito::Notifications::Source::PrivateReminder and
# friends). The web drawer and /notifications.json are untouched — title is
# push-only for now.
class AddTitleToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :title, :string, null: true
  end
end
