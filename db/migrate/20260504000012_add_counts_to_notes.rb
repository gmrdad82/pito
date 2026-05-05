# Phase B post-commit (2026-05-04) — Note revamp.
#
# Adds chars_count / words_count integer columns to `notes`. Both are
# recomputed in a `before_save` callback on the Note model from the body
# the controller passes through; the live editor in
# `app/views/notes/edit.html.erb` mirrors the same counts client-side via
# the markdown-editor Stimulus controller, so the table on the project
# show page is always in sync with what the editor shows.
#
# Backfill reads each note's body off disk via NotesFilesystem and saves
# without touching last_modified_at — the callback recomputes the counts
# and persists them in a single UPDATE per row.
class AddCountsToNotes < ActiveRecord::Migration[8.1]
  def up
    add_column :notes, :chars_count, :integer, null: false, default: 0
    add_column :notes, :words_count, :integer, null: false, default: 0

    # Backfill — best effort. Read each note's body off disk; if the file
    # is missing leave the defaults (0 / 0). Skip the timestamp bump.
    Note.reset_column_information
    Note.find_each do |note|
      body =
        begin
          NotesFilesystem.read(note)
        rescue StandardError => e
          Rails.logger.warn(
            "Note##{note.id} backfill read failed: #{e.class}: #{e.message}"
          )
          nil
        end
      next if body.nil?

      chars = body.chars.size
      words = body.scan(/\S+/).size
      # Update directly to avoid bumping `updated_at` — callbacks would
      # also bump it via touching, which is fine; we just don't need
      # last_modified_at to move.
      note.update_columns(chars_count: chars, words_count: words)
    end
  end

  def down
    remove_column :notes, :words_count
    remove_column :notes, :chars_count
  end
end
