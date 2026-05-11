# Adds a master toggle for the global keyboard-navigation surface
# (`keyboard_controller.js`). Defaults `true` — keyboard nav is on for
# everyone unless the user explicitly disables it from Settings → ui / ux.
#
# The column is NOT NULL with a default so freshly migrated rows (and
# the singleton bootstrapped from elsewhere) start with the feature
# enabled. The Stimulus controller reads the boolean off
# `<body data-keyboard-navigation-enabled="yes|no">` and self-disables
# when it sees `"no"`.
#
# Explicit `up` / `down` (rather than `change` with a `column_exists?`
# guard) so the migration is symmetrically reversible — the spec drives
# both directions on the test DB.
class AddKeyboardNavigationEnabledToAppSettings < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:app_settings, :keyboard_navigation_enabled)
    add_column :app_settings, :keyboard_navigation_enabled,
               :boolean, null: false, default: true
  end

  def down
    return unless column_exists?(:app_settings, :keyboard_navigation_enabled)
    remove_column :app_settings, :keyboard_navigation_enabled
  end
end
