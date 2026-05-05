# Phase 4 — `/projects` index revamp (Wave 2). Adds three counter-cache columns
# so the index table can render footage / notes / timelines counts without an
# N+1, and so the new sortable column headers can order by them at the SQL
# layer.
#
# Backfill of existing rows is handled in the next migration so the column
# additions stay reversible / atomic on their own.
class AddCounterCachesToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :footages_count, :integer, default: 0, null: false
    add_column :projects, :notes_count, :integer, default: 0, null: false
    add_column :projects, :timelines_count, :integer, default: 0, null: false
  end
end
