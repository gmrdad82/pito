# Drops the `chars_count` column from `notes`. The editor only shows a
# words count now; the chars count was redundant in the status bar and on
# the project show table. Reversible — `up` removes, `down` restores the
# column with the same default / null constraint it had on creation in
# `20260504000012_add_counts_to_notes`.
class RemoveCharsCountFromNotes < ActiveRecord::Migration[8.1]
  def up
    remove_column :notes, :chars_count
  end

  def down
    add_column :notes, :chars_count, :integer, null: false, default: 0
  end
end
