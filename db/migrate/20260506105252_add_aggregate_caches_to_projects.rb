# Phase 4 Wave 3.5+ — `/projects` index revamp follow-up. Adds two aggregate
# cache columns so the index renders summed values (footage duration, total
# words across notes) without recomputing on every request.
#
# These coexist with the existing `footages_count` / `notes_count` /
# `timelines_count` counter caches: the show page keeps its `(N)` headings,
# the index swaps the displayed values to the aggregates.
#
# Backfill of existing rows lives in the next migration so the column
# additions stay reversible / atomic on their own.
class AddAggregateCachesToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :footage_duration_seconds, :integer, default: 0, null: false
    add_column :projects, :notes_words_total, :integer, default: 0, null: false
  end
end
