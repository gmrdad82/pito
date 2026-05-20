# FB-132 (2026-05-21). Sessions table sortable rebuild — adds the
# `device` + `browser` columns so the /settings security pane sessions
# table can sort against indexable columns instead of executing the
# `Formatting::UserAgent.device` / `.browser` regex at query time on
# the raw `user_agent` text. Both columns are derived from `user_agent`
# at write time via a `before_validation` callback on `Session` (see
# `app/models/session.rb`); existing rows are backfilled via
# `bin/rails pito:sessions:backfill_device_browser` (see
# `lib/tasks/pito_sessions.rake`).
class AddDeviceAndBrowserToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :device, :string
    add_column :sessions, :browser, :string
    add_index :sessions, :device
    add_index :sessions, :browser
  end
end
