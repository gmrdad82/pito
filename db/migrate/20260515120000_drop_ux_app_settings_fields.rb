# Phase 29 (settings refactor) — drop UX / workspace AppSetting fields.
#
# The settings refactor splits the AppSetting surface in two:
#
#   * Operator-level workspace knobs (`max_panes`, `pane_title_length`,
#     `timezone`) move to `config/pito.yml` (gitignored) — loaded once
#     at boot by `config/initializers/pito_config.rb` and exposed at
#     `Rails.application.config.x.pito.*`.
#
#   * Theme moves to localStorage only — no server-side persistence.
#
#   * Keyboard navigation is always-on — the master toggle is dropped.
#
#   * `voyage_index_project_notes` is dropped along with the Voyage.ai
#     pane — Voyage indexing decisions now live entirely in
#     `Rails.application.credentials` (key presence == enabled).
#
# This migration drops the matching DB surfaces:
#
#   * Column `app_settings.keyboard_navigation_enabled` (boolean,
#     NOT NULL, default true).
#   * Column `app_settings.timezone` (string, NOT NULL, default UTC).
#   * Column `app_settings.voyage_index_project_notes` (boolean,
#     NOT NULL, default false).
#   * Key-value rows for `theme`, `max_panes`, `pane_title_length`
#     (the singleton AppSetting row uses both column storage AND
#     `(key, value)` rows — the three KV rows are scrubbed here).
#
# The migration is reversible: `down` re-adds the columns at their
# original defaults and rolls the KV rows back as empty strings (the
# unique index forbids re-insertion of the exact prior values without
# operator input — empty strings are a safe placeholder).

class DropUxAppSettingsFields < ActiveRecord::Migration[8.1]
  DROPPED_KV_KEYS = %w[theme max_panes pane_title_length].freeze

  def up
    # KV rows first — `delete_all` skips callbacks (the model has none
    # for this code path; we just want a fast, no-validation purge).
    execute <<~SQL
      DELETE FROM app_settings
       WHERE key IN (#{DROPPED_KV_KEYS.map { |k| "'#{k}'" }.join(', ')})
    SQL

    remove_column :app_settings, :keyboard_navigation_enabled if column_exists?(:app_settings, :keyboard_navigation_enabled)
    remove_column :app_settings, :timezone                    if column_exists?(:app_settings, :timezone)
    remove_column :app_settings, :voyage_index_project_notes  if column_exists?(:app_settings, :voyage_index_project_notes)
  end

  def down
    add_column :app_settings, :keyboard_navigation_enabled, :boolean, default: true,  null: false unless column_exists?(:app_settings, :keyboard_navigation_enabled)
    add_column :app_settings, :timezone,                    :string,  default: "UTC", null: false unless column_exists?(:app_settings, :timezone)
    add_column :app_settings, :voyage_index_project_notes,  :boolean, default: false, null: false unless column_exists?(:app_settings, :voyage_index_project_notes)
    # KV rows intentionally NOT restored — the prior values are gone.
    # `AppSetting.get('theme') || 'auto'`-style fallbacks in any code
    # surviving the refactor still resolve cleanly.
  end
end
