# Phase 4 §6.1, §6.2 — disk-side helpers for Note records.
#
# Layout: <PITO_NOTES_PATH>/projects/<project_id>/<file>.md
# Flat per project — no subdirectories.
#
# Phase 8 — tenant drop. The legacy `<tenant_id>/` segment is gone; the
# install owns the entire `<PITO_NOTES_PATH>/projects/` tree.
#
# Path-handling code is brakeman-prone. Defensive rules followed here:
#   - The relative `path` column on Note never contains directory separators.
#     `slug_filename` strips them and slugifies.
#   - Reads / writes are bracketed inside the project directory; we never
#     accept a caller-supplied absolute path or a `..` component.
#   - `ensure_within_project!` uses `File.realpath` (follows symlinks) so a
#     symlink dropped under PITO_NOTES_PATH that points outside the tree is
#     rejected. `File.expand_path` alone would only catch lexical escapes.
module NotesFilesystem
  module_function

  def root
    ENV.fetch("PITO_NOTES_PATH", "/var/lib/pito-notes")
  end

  def root_for(note)
    File.join(root, "projects", note.project_id.to_s)
  end

  # Phase B (2026-05-04) — project-level directory accessor. Used by
  # Project#after_destroy_commit to nuke the per-project notes folder once
  # all notes have been removed. Mirrors `root_for(note)`'s shape but takes
  # a Project record directly.
  def project_dir(project)
    File.join(root, "projects", project.id.to_s)
  end

  # Remove the per-project directory recursively. Defensive: returns
  # quietly if the path doesn't exist. Used during Project destruction
  # after every Note has been destroyed (and its file removed via the
  # Note `before_destroy` callback). The directory should be empty by
  # then; `rm -rf` semantics handle any leftover.
  def delete_project_dir(project)
    dir = project_dir(project)
    return unless File.directory?(dir)
    FileUtils.remove_entry(dir)
  end

  def absolute_path_for(note, relative = nil)
    relative ||= note.path
    safe_relative = sanitize_relative(relative)
    File.expand_path(safe_relative, root_for(note))
  end

  def read(note)
    path = absolute_path_for(note)
    return "" unless File.exist?(path)
    File.read(path)
  end

  def write(note, body)
    FileUtils.mkdir_p(root_for(note))
    path = absolute_path_for(note)
    ensure_within_project!(note, path)
    File.write(path, body.to_s)
    now = Time.current.to_time
    File.utime(now, now, path)
    path
  end

  def delete(note)
    path = absolute_path_for(note)
    return unless File.exist?(path)
    ensure_within_project!(note, path)
    File.delete(path)
  end

  def rename(note, new_relative)
    old_path = absolute_path_for(note)
    new_path = absolute_path_for(note, new_relative)
    ensure_within_project!(note, new_path)
    return new_path unless File.exist?(old_path)
    FileUtils.mv(old_path, new_path)
    new_path
  end

  # Convert any title-derived string into a flat filename ending in `.md`.
  # Strips path separators, lowercases, replaces non-alphanumerics with
  # hyphens, collapses runs of hyphens.
  def slug_filename(title)
    base = title.to_s
                .downcase
                .gsub(%r{[\\/\s]+}, "-")
                .gsub(/[^a-z0-9\-_]+/, "-")
                .gsub(/-+/, "-")
                .gsub(/(^-+|-+$)/, "")
    base = "untitled-note" if base.empty?
    "#{base}.md"
  end

  # Reject any `..` traversal or absolute path. Returns the sanitized basename
  # (we keep it as a relative single-segment file under the project dir).
  def sanitize_relative(relative)
    cleaned = relative.to_s.tr("\\", "/")
    raise ArgumentError, "absolute paths not allowed" if cleaned.start_with?("/")
    raise ArgumentError, "traversal not allowed" if cleaned.include?("..")
    File.basename(cleaned)
  end

  # Validate that `absolute` is contained within the project's notes directory
  # AFTER symlinks are resolved. `File.realpath` (vs `File.expand_path`) follows
  # symlinks, which is the stronger guarantee the reviewer flagged. Pito itself
  # never creates symlinks under PITO_NOTES_PATH, but an external process (or a
  # future feature) could; this guards against that case.
  #
  # `realpath` raises Errno::ENOENT for paths that don't yet exist (e.g. the
  # target of a fresh `write`). We resolve the deepest existing ancestor via
  # `realpath` and append the remaining suffix lexically. Because
  # `sanitize_relative` reduces every relative path to a single basename, the
  # suffix is always a single filename and the join is safe.
  def ensure_within_project!(note, absolute)
    project_root = canonical_path(File.expand_path(root_for(note)))
    expanded = canonical_path(absolute)
    return if expanded.start_with?(project_root + "/") || expanded == project_root
    raise ArgumentError, "path escapes project root: #{absolute}"
  end

  # Resolve `path` to its canonical form (symlinks followed). If `path` does
  # not exist yet, climb to the deepest existing ancestor, realpath that, and
  # rejoin the remaining suffix.
  def canonical_path(path)
    File.realpath(path)
  rescue Errno::ENOENT
    expanded = File.expand_path(path)
    parent = File.dirname(expanded)
    suffix = File.basename(expanded)
    # Walk up until we hit something that exists. The filesystem root always
    # exists, so this loop terminates.
    until File.exist?(parent)
      suffix = File.join(File.basename(parent), suffix)
      parent = File.dirname(parent)
    end
    File.join(File.realpath(parent), suffix)
  end
end
