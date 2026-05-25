# 2026-05-25 (collapse-to-master) — replaces the JSON `paused_targets` array
# (which held per-panel / per-sub-panel pause state) with a single boolean
# `master_sync_paused` on the singleton row. The per-target model is gone;
# only one master sync indicator exists in the UI.
class ReplacePausedTargetsWithMasterSyncPaused < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :master_sync_paused, :boolean, default: false, null: false
    remove_column :app_settings, :paused_targets, :text, default: "[]", null: false
  end
end
