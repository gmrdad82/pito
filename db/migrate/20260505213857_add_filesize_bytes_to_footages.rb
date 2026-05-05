# Phase 4 — Wave 2 foundation. Adds raw byte size to footage rows so the
# project workspace footage table can render a human-readable size. The CLI
# importer (Wave 2 Lane E, pito-rust) will start populating this column
# alongside the existing ffprobe metadata; existing rows stay null until
# they're re-probed, hence the explicit nullable declaration.
class AddFilesizeBytesToFootages < ActiveRecord::Migration[8.1]
  def change
    add_column :footages, :filesize_bytes, :bigint, null: true
  end
end
