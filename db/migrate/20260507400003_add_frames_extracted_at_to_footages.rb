# Phase 7.5 §06 — Footage thumbnails experiment.
#
# Adds `frames_extracted_at` to track the last successful frame extraction
# for a footage. The importer's bulk-frame PATCH endpoint stamps this
# column on success; the web UI / CLI can use it to detect "frames are
# stale relative to the source" once re-extraction lands as a follow-up.
#
# Nullable + no default: rows imported before this migration have no
# extraction timestamp until the importer re-runs.
class AddFramesExtractedAtToFootages < ActiveRecord::Migration[8.1]
  def change
    add_column :footages, :frames_extracted_at, :datetime
  end
end
