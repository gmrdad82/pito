# Phase 4 §3.5 — Note record mirrors a markdown file on disk under
# <PITO_NOTES_PATH>/<tenant_id>/projects/<project_id>/<file>.md (flat — no
# subdirectories per project).
#
# `embedding` is a pgvector(1024) column; populated by Notes::EmbedJob (Phase
# B) only when AppSetting.voyage_indexing_project_notes? is true AND
# AppSetting.voyage_configured? is true. Stays NULL in dev/test by default.
class Note < ApplicationRecord
  TITLE_MAX_LENGTH = 80

  # Lazy-include neighbor's pgvector helpers. The gem adds `nearest_neighbors`
  # and friends; we only need them when the search/similarity surface ships
  # (Phases 9/10), but wiring it now keeps the model future-proof.
  has_neighbors :embedding

  belongs_to :tenant
  belongs_to :project

  validates :path, presence: true,
                   uniqueness: { scope: :tenant_id }
  validates :title, presence: true, length: { maximum: TITLE_MAX_LENGTH }
  validates :last_modified_at, presence: true

  attribute :title, :string, default: "Untitled note"

  # Phase B (2026-05-04) — on-disk cleanup. When a Note is destroyed
  # (directly OR via Project#destroy → `dependent: :destroy`), delete the
  # underlying markdown file. `NotesFilesystem.delete` is a no-op if the
  # file is already missing, so this is safe to invoke unconditionally.
  # Errors are logged and swallowed so a missing-file race never stops
  # the DB-side destroy from completing.
  before_destroy :delete_note_file

  private

  def delete_note_file
    NotesFilesystem.delete(self)
  rescue StandardError => e
    Rails.logger.warn("Note##{id} file delete failed: #{e.class}: #{e.message}")
  end
end
