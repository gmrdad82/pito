# Phase 4 §3.5 — Note record mirrors a markdown file on disk under
# <PITO_NOTES_PATH>/projects/<project_id>/<file>.md (flat — no
# subdirectories per project).
#
# Phase 8 — tenant drop. Path uniqueness is now per-project (no tenant
# segment in the disk layout, no tenant_id column).
#
# `embedding` is a pgvector(1024) column; populated by Notes::EmbedJob (Phase
# B) only when AppSetting.voyage_indexing_project_notes? is true AND
# AppSetting.voyage_configured? is true. Stays NULL in dev/test by default.
class Note < ApplicationRecord
  TITLE_MAX_LENGTH = 80

  # In-memory body buffer used by the controller to pass the body through
  # to `before_save :recompute_counts`. Not persisted (the source of truth
  # is the markdown file under PITO_NOTES_PATH); only used as the input
  # for words_count recomputation.
  attr_accessor :body_for_counts

  # Lazy-include neighbor's pgvector helpers. The gem adds `nearest_neighbors`
  # and friends; we only need them when the search/similarity surface ships
  # (Phases 9/10), but wiring it now keeps the model future-proof.
  has_neighbors :embedding

  belongs_to :project, counter_cache: true

  validates :path, presence: true,
                   uniqueness: { scope: :project_id }
  validates :title, presence: true, length: { maximum: TITLE_MAX_LENGTH }
  validates :last_modified_at, presence: true

  attribute :title, :string, default: "Untitled note"

  # Phase 20 — friendly URLs. Note URLs key on the on-disk `path`
  # (possibly slash-bearing). `to_param` returns the path verbatim;
  # the router's `*path` glob delivers it back unchanged.
  def to_param
    path
  end

  # Phase B post-commit (2026-05-04) — words_count refresh.
  # The controller assigns `note.body_for_counts = body` before save; if
  # nothing was passed we keep the existing value.
  #
  # Word counting is markdown-aware and lives in `NoteHelper.word_count`
  # (extracted 2026-05-06 so the model stays storage-only). The helper
  # renders the body to HTML via Commonmarker, strips tags, then
  # tokenizes with `\p{Word}+`. `# Hi\nHow are you all doing?` reports
  # 6 words — the `#` heading marker is consumed by the markdown render
  # and never appears in the plain text.
  before_save :recompute_counts

  # Phase 4 Wave 3.5+ — `/projects` index aggregates. Keep the parent
  # project's `notes_words_total` cache in sync whenever a note's
  # `words_count` changes, the row moves to a different project, or the
  # row is destroyed. Counter-cache columns (`notes_count`) handle the
  # row-count; this callback handles the SUM-of-words display.
  after_save :recompute_project_notes_words,
             if: :saved_change_relevant_to_notes_words?
  after_save :refresh_previous_project_notes_words,
             if: :saved_change_to_project_id?
  after_destroy :recompute_project_notes_words

  # Phase B (2026-05-04) — on-disk cleanup. When a Note is destroyed
  # (directly OR via Project#destroy → `dependent: :destroy`), delete the
  # underlying markdown file. `NotesFilesystem.delete` is a no-op if the
  # file is already missing, so this is safe to invoke unconditionally.
  # Errors are logged and swallowed so a missing-file race never stops
  # the DB-side destroy from completing.
  before_destroy :delete_note_file

  private

  def recompute_counts
    return if body_for_counts.nil?

    self.words_count = NoteHelper.word_count(body_for_counts)
  end

  # Re-sums the parent project's notes word counts and writes the cached
  # total via `update_columns`. `find_by` (not `find`) is intentional:
  # when a Project is destroyed, `dependent: :destroy` cascades through
  # to its notes; by the time each note's after_destroy fires, the
  # project row is already gone. Silently no-op in that case.
  def recompute_project_notes_words
    return unless project_id
    project = Project.find_by(id: project_id)
    return unless project
    project.update_columns(
      notes_words_total: project.notes.sum(:words_count).to_i
    )
  end

  def saved_change_relevant_to_notes_words?
    saved_change_to_words_count? || saved_change_to_project_id?
  end

  # When a note moves between projects, the OLD project's cache still
  # includes this row's words. Recompute it from `saved_changes`.
  def refresh_previous_project_notes_words
    previous_project_id = saved_change_to_project_id&.first
    return unless previous_project_id
    previous = Project.find_by(id: previous_project_id)
    return unless previous
    previous.update_columns(
      notes_words_total: previous.notes.sum(:words_count).to_i
    )
  end

  def delete_note_file
    NotesFilesystem.delete(self)
  rescue StandardError => e
    Rails.logger.warn("Note##{id} file delete failed: #{e.class}: #{e.message}")
  end
end
