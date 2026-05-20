class SimplifyNotificationToggles < ActiveRecord::Migration[8.1]
  # Beta 4 — F3-B-SIMPLIFY-MODEL. Collapse the per-brand routing flags
  # on `notification_delivery_channels` into two shared columns on
  # `app_settings`.
  #
  # Before:
  #   notification_delivery_channels.everything   (boolean)
  #   notification_delivery_channels.daily_digest (boolean)
  #
  # After:
  #   app_settings.notifications_send_all          (boolean)
  #   app_settings.notifications_send_daily_digest (boolean)
  #
  # Shared semantics: the two shared cols live on the canonical
  # singleton `AppSetting` row (`key = "__singleton__"`). One toggle
  # gates BOTH brands at once; per-brand webhook presence still gates
  # whether THAT brand attempts a delivery.
  #
  # Intent preservation: if EITHER brand row had `everything: true` /
  # `daily_digest: true` before the migration, the matching shared
  # flag flips on so the operator's prior choice is honoured.
  def up
    # 1. Add the two shared columns on app_settings.
    add_column :app_settings, :notifications_send_all, :boolean, default: false, null: false
    add_column :app_settings, :notifications_send_daily_digest, :boolean, default: false, null: false

    # 2. Preserve intent: OR existing per-brand flags into the shared
    #    singleton row before dropping the per-brand columns.
    any_everything   = ActiveRecord::Base.connection.select_value(
      "SELECT BOOL_OR(everything) FROM notification_delivery_channels"
    )
    any_daily_digest = ActiveRecord::Base.connection.select_value(
      "SELECT BOOL_OR(daily_digest) FROM notification_delivery_channels"
    )

    # Active Record Encryption is involved on `app_settings.value` so
    # we go through the model (not raw SQL) to keep the singleton row
    # discoverable by `AppSetting.singleton_row` afterwards.
    singleton = AppSetting.find_or_initialize_by(key: AppSetting::SINGLETON_KEY)
    singleton.value = "singleton" if singleton.value.blank?
    singleton.notifications_send_all = !!any_everything
    singleton.notifications_send_daily_digest = !!any_daily_digest
    singleton.save!

    # 3. Drop the per-brand toggle columns.
    remove_column :notification_delivery_channels, :everything
    remove_column :notification_delivery_channels, :daily_digest
  end

  def down
    add_column :notification_delivery_channels, :everything,   :boolean, default: false, null: false
    add_column :notification_delivery_channels, :daily_digest, :boolean, default: false, null: false

    # Best-effort restore: copy the shared values onto BOTH brand rows
    # if they exist. The migration is dev-only — production never sees it.
    send_all = ActiveRecord::Base.connection.select_value(
      "SELECT notifications_send_all FROM app_settings WHERE key = '__singleton__' LIMIT 1"
    )
    send_dd = ActiveRecord::Base.connection.select_value(
      "SELECT notifications_send_daily_digest FROM app_settings WHERE key = '__singleton__' LIMIT 1"
    )
    if send_all || send_dd
      ActiveRecord::Base.connection.execute(
        "UPDATE notification_delivery_channels SET " \
        "everything = #{send_all ? 'TRUE' : 'FALSE'}, " \
        "daily_digest = #{send_dd ? 'TRUE' : 'FALSE'}"
      )
    end

    remove_column :app_settings, :notifications_send_all
    remove_column :app_settings, :notifications_send_daily_digest
  end
end
