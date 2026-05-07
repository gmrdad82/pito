class SetFootagesTenantIdNotNull < ActiveRecord::Migration[8.1]
  # Phase 5A §5.2 — `footages.tenant_id` was originally introduced
  # nullable in Phase 4 because the model auto-denormalizes it from
  # `project.tenant_id` in a `before_validation` callback. Tighten
  # the column to NOT NULL — every existing row already has it
  # populated via that callback, but backfill defensively first in
  # case a hand-written INSERT slipped through.

  def up
    execute(<<~SQL.squish)
      UPDATE footages
      SET tenant_id = projects.tenant_id
      FROM projects
      WHERE footages.project_id = projects.id
        AND footages.tenant_id IS NULL
    SQL

    change_column_null :footages, :tenant_id, false
  end

  def down
    change_column_null :footages, :tenant_id, true
  end
end
