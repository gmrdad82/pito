# frozen_string_literal: true

# Persist the per-conversation chatbox scope so a reload restores it:
#   scope_channel — the shift+tab channel filter (e.g. "@all", "@manfygreats")
#   stats_period  — the shift+space stats window (e.g. "7d", "28d", "lifetime")
# Both carry sensible defaults so existing rows and new conversations start at
# "@all" / "7d" with no backfill job.
class AddScopeToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :scope_channel, :string, null: false, default: "@all"
    add_column :conversations, :stats_period, :string, null: false, default: "7d"
  end
end
