# frozen_string_literal: true

# Severity level for a notification, driving the emoji + color of its rich
# Slack/Discord webhook delivery. info | success | warning | error.
class AddLevelToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :level, :string, null: false, default: "info"
  end
end
