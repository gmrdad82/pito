# Phase 26 — 01a. Timezone foundation.
#
# Pin UTC-storage / user-tz-render as the app-wide contract for every
# time value. `time_zone` is a string column carrying an IANA name
# (`Europe/Bucharest`, `America/Los_Angeles`, etc.) plus the
# Rails-friendly aliases (`UTC`, etc.). Default `"Etc/UTC"` doubles as
# the "never set" sentinel — the first authenticated page load detects
# the browser zone via JS and silently PATCHes the user's row.
#
# No index — `time_zone` is read off `Current.user` per request, never
# the target of a lookup or join.
class AddTimeZoneToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :time_zone, :string, null: false, default: "Etc/UTC"
  end
end
