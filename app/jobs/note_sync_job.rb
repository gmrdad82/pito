# Phase 4 §6.3 — Sidekiq cron reconciliation: filesystem ↔ Note rows.
#
# Schedule: every 5 minutes by default (config/sidekiq_cron.yml). Per tenant:
#
#   1. Set `tenant.notes_syncing_at = Time.current` (acquires the lock).
#   2. Walk <PITO_NOTES_PATH>/<tenant_id>/projects/*/*.md (flat per project).
#   3. Per .md file:
#      - file + DB record + mtime > last_modified_at → re-parse title,
#        update title + last_modified_at, enqueue Notes::EmbedJob.
#      - file + no DB record → create record (parse title, mtime → ts).
#   4. DB record without a file → destroy record (hard delete).
#   5. ensure { tenant.update!(notes_syncing_at: nil) }.
#
# The `ensure` block guarantees the lock clears even on raise. A 5-minute
# stale-lock shield in NotesLockGuard keeps the UI usable if a job dies
# without running its ensure (process kill / OOM).
class NoteSyncJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(tenant_id)
    tenant = Tenant.find_by(id: tenant_id)
    return unless tenant

    tenant.update!(notes_syncing_at: Time.current)

    reconcile_each_file(tenant)
    destroy_orphan_records(tenant)
  ensure
    Tenant.where(id: tenant_id).update_all(notes_syncing_at: nil)
  end

  private

  # Walk every project directory once and reconcile against the DB.
  def reconcile_each_file(tenant)
    base = tenant_root(tenant)
    return unless Dir.exist?(base)

    Dir.glob(File.join(base, "projects", "*", "*.md")).each do |abs_path|
      project_id = File.basename(File.dirname(abs_path)).to_i
      next unless project_id.positive?

      project = tenant.projects.find_by(id: project_id)
      next unless project

      reconcile_one(tenant: tenant, project: project, abs_path: abs_path)
    end
  end

  def reconcile_one(tenant:, project:, abs_path:)
    relative = File.basename(abs_path)
    note = Note.find_by(tenant_id: tenant.id, path: relative)
    file_mtime = File.mtime(abs_path)
    body = File.read(abs_path)
    title = NoteTitleParser.parse(body)

    if note.nil?
      created = project.notes.create(
        tenant: tenant,
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
  def destroy_orphan_records(tenant)
    base = tenant_root(tenant)
    tenant.notes.find_each do |note|
      project_dir = File.join(base, "projects", note.project_id.to_s)
      abs = File.join(project_dir, note.path)
      next if File.exist?(abs)
      note.destroy
    end
  end

  def enqueue_embed(note)
    Notes::EmbedJob.perform_async(note.id)
  end

  def tenant_root(tenant)
    File.join(NotesFilesystem.root, tenant.id.to_s)
  end
end
