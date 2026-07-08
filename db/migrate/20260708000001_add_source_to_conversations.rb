# frozen_string_literal: true

# G130 (MCP): conversation-space separation. Every conversation is either an
# "app" conversation (the owner's real scrollback — the web/APK/TUI sidebar and
# resume) or the single "mcp" anchor the read-only MCP Executor dispatches
# against (context only; it never gains events). The default "app" backfills
# existing rows atomically (Postgres fast default), so no separate backfill step
# is needed. Indexed because singleton / by_recent_activity filter on it.
class AddSourceToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :source, :string, null: false, default: "app"
    add_index :conversations, :source
  end
end
