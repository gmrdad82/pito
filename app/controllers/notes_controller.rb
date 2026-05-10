# Phase 4 §6.2, §6.4, §6.5 — Note controller.
#
# Lifecycle:
#   - create: writes `untitled-note-<unix_ts>.md` (empty file) and creates
#     the Note record in one transaction; failure on either side rolls back.
#   - update: writes the new body to disk, updates last_modified_at, parses
#     the title from the first ATX `# heading` (§6.5), persists the title.
#   - destroy: removes the file and destroys the record.
#
# Every mutating action checks the install-wide lock (§6.4): when the
# notes sync timestamp is fresh (≤ 5 min), we return 423 Locked with a
# `{"error":"notes_syncing","retry_after":30}` JSON body.
#
# Filesystem layout (Phase 8 — tenant drop):
#   <PITO_NOTES_PATH>/projects/<project_id>/<file>.md
class NotesController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :set_note, only: [ :show, :update, :destroy ]
  before_action :reject_if_notes_syncing,
                only: [ :create, :update, :destroy ]

  def index
    # Top-level list — kept for the Phase A routing helper. The project notes
    # pane (§9.1) is the actual surface; this is a debugging/admin view.
    @notes = Note.order(last_modified_at: :desc).limit(200)
  end

  # Phase 4 §6.4 — `[ scan now ]` enqueues an immediate NoteSyncJob.
  # Still subject to the lock on the next request: if the lock is fresh, the
  # banner stays up.
  def scan
    NoteSyncJob.perform_async
    redirect_back(
      fallback_location: root_path,
      notice: "notes scan enqueued."
    )
  end

  # Phase B post-commit (2026-05-04) — Note revamp. The show route IS the
  # editor. Two panes (rendered preview / source textarea) and a status bar
  # of chars/words. The title is auto-derived from the body's first ATX H1
  # in `update`; there is no title input on the form.
  def show
    @project = @note.project
    @body = NotesFilesystem.read(@note)
  end

  def create
    project = Project.find(params[:project_id])

    timestamp = Time.current.to_i
    relative_path = "untitled-note-#{timestamp}.md"

    note = nil
    Note.transaction do
      note = project.notes.create!(
        path: relative_path,
        title: "Untitled note",
        last_modified_at: Time.current
      )
      NotesFilesystem.write(note, "")
    end

    # Phase B post-commit — single canonical editor URL is the show route.
    redirect_to note_path(note), notice: "note created."
  rescue ActiveRecord::RecordInvalid, IOError, Errno::EACCES => e
    Rails.logger.warn("Note create failed: #{e.class}: #{e.message}")
    redirect_to project_path(project), alert: "couldn't create note."
  end

  # Phase B post-commit (2026-05-04) — title is no longer accepted as input.
  # It is derived from the body's first ATX H1 (or the fallback). The
  # filename can change as a side effect of a title change; that path
  # rename still flows through NotesFilesystem.
  def update
    body = params.dig(:note, :body).to_s

    Note.transaction do
      derived_title = NoteTitleParser.parse(body)
      truncated = derived_title[0, Note::TITLE_MAX_LENGTH]

      # If the derived title changed and produces a new on-disk path,
      # rename the file. Falls back silently if the slug matches.
      if truncated != @note.title
        new_path = NotesFilesystem.slug_filename(truncated)
        if new_path != @note.path
          NotesFilesystem.rename(@note, new_path)
          @note.path = new_path
        end
        @note.title = truncated
      end

      NotesFilesystem.write(@note, body)
      @note.body_for_counts = body
      @note.last_modified_at = Time.current
      @note.save!
    end

    redirect_to project_path(@note.project), notice: "note saved."
  rescue ActiveRecord::RecordInvalid, IOError, Errno::EACCES => e
    Rails.logger.warn("Note update failed: #{e.class}: #{e.message}")
    redirect_to note_path(@note), alert: "couldn't save note."
  end

  # Phase B post-commit (2026-05-04) — Item 4. The on-disk cleanup is
  # owned by Note's `before_destroy :delete_note_file` callback (handles
  # Project#destroy → `dependent: :destroy` cascades, console-driven
  # destroys, bulk-delete jobs). The controller no longer calls
  # NotesFilesystem.delete explicitly; one source of truth.
  def destroy
    @note.destroy!
    redirect_to project_path(@note.project), notice: "note deleted."
  end

  private

  def set_note
    @note = Note.find(params[:id])
  end

  # Phase 4 §6.4 — return 423 Locked when notes are syncing install-wide.
  # Both HTML and JSON callers get a clear error response. The view-side
  # banner in `_notes_pane.html.erb` keeps the UI consistent.
  def reject_if_notes_syncing
    return unless NotesLockGuard.locked?

    respond_to do |format|
      format.html do
        redirect_back(
          fallback_location: root_path,
          alert: "notes are syncing — try again in a moment.",
          status: :see_other
        )
      end
      format.json do
        render json: {
          error: "notes_syncing",
          retry_after: NotesLockGuard.retry_after_seconds
        }, status: :locked
      end
    end
  end
end
