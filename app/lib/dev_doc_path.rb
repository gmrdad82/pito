# DevDocPath — read-side path safety for the MCP Dev KB surface.
#
# Used by `list_docs` and `read_doc` to validate caller-supplied paths
# BEFORE any filesystem access. The contract is intentionally narrow:
#
# - Reject absolute paths (anything beginning with "/").
# - Reject paths whose cleanpath contains ".." segments.
# - Reject anything whose extension is not ".md".
# - The resolved path must be inside `Rails.root.join("docs")` OR be
#   exactly `Rails.root.join("CLAUDE.md")`. Anything else is rejected.
#
# Validation is purely lexical and structural (Pathname#cleanpath, no
# realpath, no stat) — failures never depend on what's on disk. The
# helper does NOT touch the write side; `save_note` writes to a
# hard-coded folder with a server-derived filename and never feeds
# user input into the path computation.
module DevDocPath
  module_function

  # Returns the validated absolute Pathname for a relative input, or
  # raises DevDocPath::Error with a clear message. Callers should rescue
  # `DevDocPath::Error` and translate to an MCP error response.
  def resolve(relative_path)
    raise Error, "path is required" if relative_path.nil? || relative_path.to_s.strip.empty?

    raw = relative_path.to_s

    # Lexical rejections first — never look at the filesystem before the
    # input has been cleared.
    raise Error, "path must be relative (no leading '/')" if raw.start_with?("/")

    cleaned = Pathname.new(raw).cleanpath
    raise Error, "path must be relative (no leading '/')" if cleaned.absolute?
    raise Error, "path must not contain '..' segments" if cleaned.to_s.split("/").include?("..")
    raise Error, "extension must be .md" unless cleaned.extname == ".md"

    root = Rails.root
    docs_root = root.join("docs").cleanpath
    claude_md = root.join("CLAUDE.md").cleanpath

    candidate = root.join(cleaned).cleanpath

    return candidate if candidate == claude_md
    return candidate if inside?(candidate, docs_root)

    raise Error, "path must be inside docs/ or be CLAUDE.md"
  end

  # True if `path` is exactly `root` or any descendant. Both arguments
  # must already be cleanpath'd absolute Pathnames.
  def inside?(path, root)
    return false unless path.absolute? && root.absolute?
    return true if path == root

    path_parts = path.to_s.split("/")
    root_parts = root.to_s.split("/")
    return false if path_parts.length <= root_parts.length

    path_parts.first(root_parts.length) == root_parts
  end

  class Error < StandardError; end
end
