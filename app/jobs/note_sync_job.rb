# Phase 4 §6.3 — Sidekiq cron reconciliation: filesystem ↔ Note rows.
#
# Schedule: every 5 minutes by default (config/sidekiq_cron.yml).
#
# Phase 8 — tenant drop. The job runs install-wide; the legacy
# `tenant.notes_syncing_at` lock now lives on `AppSetting` (see
# `NotesLockGuard`). The job walks
# `<PITO_NOTES_PATH>/projects/*/*.md` (flat per project).
#
#   1. Acquire the install-wide lock (sets the syncing timestamp).
#   2. Walk every `<root>/projects/<project_id>/*.md`.
#   3. Per .md file:
#      - file + DB record + mtime > last_modified_at → re-parse title,
#        update title + last_modified_at, enqueue Notes::EmbedJob.
#      - file + no DB record → create record (parse title, mtime → ts).
#   4. DB record without a file → destroy record (hard delete).
#   5. ensure { release the install-wide lock }.
#
# The `ensure` block guarantees the lock clears even on raise. A 5-minute
# stale-lock shield in NotesLockGuard keeps the UI usable if a job dies
# without running its ensure (process kill / OOM).
class NoteSyncJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  # `perform` accepts an optional positional arg for backwards
  # compatibility with the previous `perform(tenant_id)` signature.
  # Any value passed in is ignored — the job is install-wide.
  def perform(_legacy_tenant_id = nil)
    NotesLockGuard.acquire!
    reconcile_each_file
    destroy_orphan_records
  ensure
    NotesLockGuard.release!
  end

  private

  # Walk every project directory once and reconcile against the DB.
  def reconcile_each_file
    base = NotesFilesystem.root
    return unless Dir.exist?(base)

    Dir.glob(File.join(base, "projects", "*", "*.md")).each do |abs_path|
      project_id = File.basename(File.dirname(abs_path)).to_i
      next unless project_id.positive?

      project = Project.find_by(id: project_id)
      next unless project

      reconcile_one(project: project, abs_path: abs_path)
    end
  end

  def reconcile_one(project:, abs_path:)
    relative = File.basename(abs_path)
    note = Note.find_by(project_id: project.id, path: relative)
    file_mtime = File.mtime(abs_path)
    body = File.read(abs_path)
    title = NoteTitleParser.parse(body)

    if note.nil?
      created = project.notes.create(
        path: relative,
        title: title,
        last_modified_at: file_mtime
      )
      enqueue_embed(created) if created.persisted?
    elsif file_mtime > note.last_modified_at
      note.update!(title: title, last_modified_at: file_mtime)
      enqueue_embed(note)
    end
  end

  # Hard-delete any Note row whose file disappeared from disk.
  def destroy_orphan_records
    base = NotesFilesystem.root
    Note.find_each do |note|
      project_dir = File.join(base, "projects", note.project_id.to_s)
      abs = File.join(project_dir, note.path)
      next if File.exist?(abs)
      note.destroy
    end
  end

  def enqueue_embed(note)
    Notes::EmbedJob.perform_async(note.id)
  end
end
