class AllowNullWebhookUrlOnNotificationDeliveryChannels < ActiveRecord::Migration[8.1]
  # 2026-05-16 webhook-clear UX tweak.
  #
  # The Discord / Slack webhook panes now support a "clear the integration"
  # gesture: blank the URL field, click `[update]`, and the row persists
  # with `webhook_url = nil` + both routing flags reset to false. The model
  # carries the invariant "URL nil implies both flags false" so the same
  # state is reachable from any surface (web form, MCP tool, future CLI).
  #
  # Previously the column was NOT NULL — the only ways to "turn the
  # integration off" were to delete the row or to leave both flags false
  # with a valid URL still pinned. Allowing NULL gives the panes a clean
  # "cleared" state to render (empty URL field, both checkboxes
  # unchecked) without inventing a tombstone string.
  def change
    change_column_null :notification_delivery_channels, :webhook_url, true
  end
end
