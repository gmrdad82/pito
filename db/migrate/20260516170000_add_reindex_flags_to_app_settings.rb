class AddReindexFlagsToAppSettings < ActiveRecord::Migration[8.1]
  # Phase 32 follow-up (2026-05-16). Three-layer reindex lock + live UI.
  #
  # Layer 1 (DB flag — this migration). `reindex_running` + `reindex_started_at`
  # are install-wide singletons that the `SettingsController#reindex`
  # action consults BEFORE enqueueing `ReindexAllJob`. If the flag is
  # set the controller short-circuits with an alert; otherwise it
  # flips the flag, stamps `reindex_started_at`, and enqueues the job.
  # The job clears both fields in an `ensure` block so a worker crash
  # never leaves the flag stuck (and `bin/rails pito:state:clear_reindex_lock`
  # is the operator escape hatch for the residual-stuck-flag case).
  #
  # Layer 2 (Sidekiq uniqueness — `sidekiq_options lock: :until_executed`
  # in `ReindexAllJob`). Drops a duplicate `perform_later` if one is
  # already in flight.
  #
  # Layer 3 (UI gate — Stack pane Voyage section renders the `dot-loader`
  # indicator while the flag is true, the `[reindex]` link otherwise).
  # The job broadcasts a Turbo Stream replace to the `reindex_status`
  # stream on the `ensure` cleanup so every open `/settings` tab swaps
  # back to the idle link without a page refresh.
  #
  # The two columns are install-wide singletons (pito is single-install,
  # multi-user per ADR 0003); they live on the `app_settings` table
  # alongside the existing key/value rows. Default `reindex_running:
  # false` keeps existing rows valid post-migration; `reindex_started_at`
  # is nullable because the idle steady state has no start stamp.
  def change
    add_column :app_settings, :reindex_running, :boolean, default: false, null: false
    add_column :app_settings, :reindex_started_at, :datetime, null: true
  end
end
