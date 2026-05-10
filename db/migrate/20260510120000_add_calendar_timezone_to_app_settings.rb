# Phase 15 §1 — Calendar Data Model.
#
# Adds the install-level `timezone` column to `app_settings`. Default `"UTC"`.
# The column is a real column on every row (the `app_settings` table is
# key/value-shaped, but `AppSetting.first` is the de-facto singleton; reads
# go through `AppSetting.first&.timezone`).
class AddCalendarTimezoneToAppSettings < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:app_settings, :timezone)

    add_column :app_settings, :timezone, :string, null: false, default: "UTC"
  end
end
