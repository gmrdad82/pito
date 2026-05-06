# Recompute `notes.words_count` against the new markdown-aware
# tokenizer (`NoteHelper.word_count`). The original
# `20260504000012_add_counts_to_notes` backfill used a whitespace
# tokenizer (`body.scan(/\S+/).size`); switching to the
# Commonmarker-render-then-tokenize approach changes counts on existing
# rows (e.g. a single `# Hi\nHow are you all doing?` note moves from 7
# to 6).
#
# `update_columns` skips callbacks/validations — we are setting the
# canonical value computed by the helper, not triggering another
# recompute. `find_each` keeps memory bounded on larger note sets.
#
# One-way: the previous algorithm is not preserved, so `down` is a
# documented no-op. Reverting `up` is meaningless without restoring
# the old algorithm too; if a future Wave needs different counting,
# add a NEW migration rather than rolling this one back.
class BackfillNoteWordsCount < ActiveRecord::Migration[8.1]
  def up
    Note.find_each(batch_size: 200) do |note|
      body = NotesFilesystem.read(note)
      note.update_columns(words_count: NoteHelper.word_count(body))
    rescue StandardError => e
      Rails.logger.warn("BackfillNoteWordsCount: skipping note ##{note.id} (#{e.class}: #{e.message})")
    end
  end

  def down
    # No-op — backfill is one-way; old algorithm not preserved.
  end
end
