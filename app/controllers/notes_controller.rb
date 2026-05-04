# Phase 4 §6.2, §6.4, §6.5 — Note controller.
#
# Lifecycle:
#   - create: writes `untitled-note-<unix_ts>.md` (empty file) and creates
#     the Note record in one transaction; failure on either side rolls back.
#   - update: writes the new body to disk, updates last_modified_at, parses
#     the title from the first ATX `# heading` (§6.5), persists the title.
#   - destroy: removes the file and destroys the record.
#
# Every mutating action checks the tenant-wide lock (§6.4): when
# `tenant.notes_syncing_at` is fresh (≤ 5 min), we return 423 Locked with a
# `{"error":"notes_syncing","retry_after":30}` JSON body.
#
# Filesystem layout:
#   <PITO_NOTES_PATH>/<tenant_id>/projects/<project_id>/<file>.md
class NotesController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :set_note, only: [ :show, :edit, :update, :destroy ]
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
    tenant = Tenant.order(:id).first
    NoteSyncJob.perform_async(tenant.id) if tenant
    redirect_back(
      fallback_location: root_path,
      notice: "notes scan enqueued."
    )
  end

  def show
    redirect_to project_path(@note.project)
  end

  def edit
    @project = @note.project
    @body = NotesFilesystem.read(@note)
  end

  def create
    project = Project.find(params[:project_id])
    tenant = project.tenant

    timestamp = Time.current.to_i
    relative_path = "untitled-note-#{timestamp}.md"

    note = nil
    Note.transaction do
      note = project.notes.create!(
        tenant: tenant,
        path: relative_path,
        title: "Untitled note",
        last_modified_at: Time.current
      )
      NotesFilesystem.write(note, "")
    end

    redirect_to edit_note_path(note), notice: "note created."
  rescue ActiveRecord::RecordInvalid, IOError, Errno::EACCES => e
    Rails.logger.warn("Note create failed: #{e.class}: #{e.message}")
    redirect_to project_path(project), alert: "couldn't create note."
  end

  def update
    body = params.dig(:note, :body).to_s
    new_title = params.dig(:note, :title).to_s

    Note.transaction do
      # Title rename → slugify + rename file. Body update writes contents.
      if new_title.present? && new_title != @note.title
        truncated = new_title[0, Note::TITLE_MAX_LENGTH]
        new_path = NotesFilesystem.slug_filename(truncated)
        if new_path != @note.path
          NotesFilesystem.rename(@note, new_path)
          @note.path = new_path
        end
        @note.title = truncated
      else
        # Pull title from the body's first ATX H1, falling back to "Untitled note".
        @note.title = NoteTitleParser.parse(body)
      end

      NotesFilesystem.write(@note, body)
      @note.last_modified_at = Time.current
      @note.save!
    end

    redirect_to project_path(@note.project), notice: "note saved."
  rescue ActiveRecord::RecordInvalid, IOError, Errno::EACCES => e
    Rails.logger.warn("Note update failed: #{e.class}: #{e.message}")
    redirect_to edit_note_path(@note), alert: "couldn't save note."
  end

  def destroy
    Note.transaction do
      NotesFilesystem.delete(@note)
      @note.destroy!
    end
    redirect_to project_path(@note.project), notice: "note deleted."
  end

  private

  def set_note
    @note = Note.find(params[:id])
  end

  # Phase 4 §6.4 — return 423 Locked when the tenant's notes are syncing.
  # Both HTML and JSON callers get a clear error response. The view-side
  # banner in `_notes_pane.html.erb` keeps the UI consistent.
  def reject_if_notes_syncing
    tenant = NotesLockGuard.locked_tenant_for(self)
    return unless tenant && NotesLockGuard.locked?(tenant)

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
