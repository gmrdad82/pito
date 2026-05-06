# Phase 4 Wave 3.5+ — `/projects` index revamp follow-up. Backfills the two
# aggregate cache columns added in the previous migration. Sums each project's
# footage durations and notes word counts via SQL; subsequent writes stay in
# sync via after_save / after_destroy callbacks on Footage / Note.
#
# Rollback is intentionally a no-op — the columns themselves are dropped by
# rolling back the prior migration; resetting the values to zero adds nothing.
class BackfillProjectAggregateCaches < ActiveRecord::Migration[8.1]
  def up
    Project.reset_column_information

    Project.find_each(batch_size: 200) do |project|
      project.update_columns(
        footage_duration_seconds: project.footages.sum(:duration_seconds).to_i,
        notes_words_total: project.notes.sum(:words_count).to_i
      )
    end
  end

  def down
    # No-op — backfill is one-way. The aggregate columns are dropped by
    # rolling back AddAggregateCachesToProjects; zeroing them here would
    # add nothing.
  end
end
