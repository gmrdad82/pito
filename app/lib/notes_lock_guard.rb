# Phase 4 §6.4 — install-wide notes-syncing lock.
#
# The `NoteSyncJob` walks the disk install-wide. While it runs, mutating
# Note operations are rejected so concurrent edits do not race the
# reconciliation. The lock is encoded as an AppSetting row keyed by
# `notes_syncing_at`; a "fresh" timestamp (within the last 5 minutes)
# is the active-lock signal, anything older is treated as a stale
# lock (the job died mid-flight) and writes are allowed.
#
# Phase 8 — tenant drop. The lock used to live on `Tenant#notes_syncing_at`.
# After the tenant model went away, the lock moved to a singleton
# AppSetting row. The 5-minute stale-lock window is preserved.
#
# Three callers:
#   1. NotesController mutating actions — return 423 Locked when locked.
#   2. Notes pane partial — render banner + disable save buttons when locked.
#   3. Specs — `acquire!` / `release!` to assert lock state.
module NotesLockGuard
  STALE_AFTER = 5.minutes
  KEY = "notes_syncing_at".freeze

  module_function

  # True iff a notes sync is currently in progress (lock fresh).
  # Backward-compatible: callers that previously passed a tenant
  # argument (`locked?(tenant)`) still work — the argument is ignored.
  def locked?(*_args)
    ts = current_lock_timestamp
    return false if ts.blank?
    Time.current - ts <= STALE_AFTER
  end

  # Seconds the client should wait before retrying. Always 30s — tweak when
  # real syncs surface concrete duration data.
  def retry_after_seconds
    30
  end

  # Acquire the install-wide lock by stamping the current time on the
  # AppSetting row. Idempotent — re-acquiring just refreshes the stamp.
  def acquire!
    AppSetting.set(KEY, Time.current.iso8601(6))
  end

  # Release the lock. Safe to call even if no lock is held.
  def release!
    record = AppSetting.find_by(key: KEY)
    record&.update!(value: nil)
  rescue ActiveRecord::RecordInvalid
    # AppSetting validates `value` presence; clearing is implemented
    # by deletion so the row never stores blank state.
    record&.destroy
  end

  # Resolve the project in scope for a controller call. Used by the
  # 423 Locked response path so callers can mention the project they
  # tried to mutate (the lock itself is install-wide; this is purely
  # informational and may return nil).
  def locked_project_for(controller)
    note_id = controller.params[:id]
    return Note.find(note_id).project if note_id.present? && Note.exists?(note_id)

    project_id = controller.params[:project_id]
    return Project.find(project_id) if project_id.present? && Project.exists?(project_id)

    nil
  end

  # Backward-compat shim. Existing controller code calls
  # `locked_tenant_for(self)` to figure out the lock context;
  # the install-wide lock no longer keys on a tenant, so this
  # returns a sentinel object the lock check can ignore.
  def locked_tenant_for(controller)
    locked_project_for(controller)
  end

  def current_lock_timestamp
    raw = AppSetting.get(KEY)
    return nil if raw.blank?
    Time.zone.parse(raw)
  rescue ArgumentError, TypeError
    nil
  end
end
