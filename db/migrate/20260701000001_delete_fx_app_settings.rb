# frozen_string_literal: true

# Item 18: the `/config motion` toggle and `/config fx` reveal-effect were
# removed. Delete their now-orphaned key/value rows from app_settings.
class DeleteFxAppSettings < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM app_settings WHERE key IN ('fx_enabled', 'fx_effect')"
  end

  def down
    # No-op: the fx/motion settings were removed in item 18; nothing to restore.
  end
end
