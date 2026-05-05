# Phase 4 — `/projects` index revamp (Wave 2). Backfills the three
# counter-cache columns added in the previous migration. Runs through
# `Project.reset_counters` so the values match what `belongs_to
# counter_cache: true` would track on subsequent writes.
#
# Rollback: down resets every counter to zero, which matches the column
# defaults from the prior migration.
class BackfillProjectCounterCaches < ActiveRecord::Migration[8.1]
  ASSOCIATIONS = %i[footages notes timelines].freeze

  def up
    Project.reset_column_information

    Project.find_each do |project|
      ASSOCIATIONS.each do |assoc|
        next unless Project.reflect_on_association(assoc)
        Project.reset_counters(project.id, assoc)
      end
    end
  end

  def down
    Project.reset_column_information
    Project.update_all(footages_count: 0, notes_count: 0, timelines_count: 0)
  end
end
