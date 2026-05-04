# Phase 4 §6.4 — tenant-wide notes-syncing lock.
#
# `Tenant#notes_syncing_at` is set by `NoteSyncJob` while it walks the disk.
# A "fresh" timestamp (within the last 5 minutes) is the active-lock signal.
# Older timestamps are treated as a stale lock — the job died mid-flight and
# never cleared the column — so we let writes through. The 5-minute window
# is a safety shield, NOT a wait time.
#
# Three callers:
#   1. NotesController mutating actions — return 423 Locked when locked.
#   2. Notes pane partial — render banner + disable save buttons when locked.
#   3. Specs — flip the column with a known time, assert lock state.
module NotesLockGuard
  STALE_AFTER = 5.minutes

  module_function

  # True iff the tenant's notes are currently being synced (lock fresh).
  def locked?(tenant)
    return false if tenant.nil?
    ts = tenant.notes_syncing_at
    return false if ts.blank?
    Time.current - ts <= STALE_AFTER
  end

  # Seconds the client should wait before retrying. Always 30s — tweak when
  # real syncs surface concrete duration data.
  def retry_after_seconds
    30
  end

  # Resolve the tenant in scope for a controller call. Resolves via:
  #   1. Note params (params[:id] for update/destroy, project_id for create)
  #   2. fallback to the singleton tenant
  # Returns nil if no tenant could be resolved.
  def locked_tenant_for(controller)
    note_id = controller.params[:id]
    return Note.find(note_id).tenant if note_id.present? && Note.exists?(note_id)

    project_id = controller.params[:project_id]
    return Project.find(project_id).tenant if project_id.present? && Project.exists?(project_id)

    Tenant.order(:id).first
  end
end
