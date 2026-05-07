module Mcp
  module Tools
    class ListDocs < MCP::Tool
      tool_name "list_docs"
      description "List markdown files under docs/ (and CLAUDE.md when matched). Filter by name_pattern (glob, default '*.md') and prefix (relative to docs/, default ''). Sort by mtime_desc / mtime_asc / path. Returns array of {path, last_modified_at, size_bytes, first_heading}."

      SORTS = %w[mtime_desc mtime_asc path].freeze

      input_schema(
        type: "object",
        properties: {
          name_pattern: { type: "string", description: "Glob-style filename pattern (default '*.md')" },
          prefix:       { type: "string", description: "Relative-to-docs/ subpath filter, e.g. 'plans/' (default '')" },
          sort:         { type: "string", enum: SORTS, description: "Sort order (default 'mtime_desc')" },
          limit:        { type: "integer", description: "Max results, 1–500 (default 50)" }
        }
      )

      annotations(read_only_hint: true)

      def self.call(name_pattern: "*.md", prefix: "", sort: "mtime_desc", limit: 50)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::DEV_READ)
        return scope_err if scope_err

        name_pattern = name_pattern.to_s
        name_pattern = "*.md" if name_pattern.empty?
        prefix = prefix.to_s

        unless SORTS.include?(sort.to_s)
          return error_response("sort must be one of: #{SORTS.join(', ')} (got #{sort.inspect})")
        end

        limit = limit.to_i
        limit = 50 if limit <= 0
        limit = [ [ limit, 1 ].max, 500 ].min

        # Refuse anything that smells like an escape attempt. The prefix
        # is appended to docs/ by glob; rejecting up-front avoids sneaky
        # patterns like "../" leaking outside docs/.
        if prefix.start_with?("/")
          return error_response("prefix must be relative (no leading '/')")
        end
        if Pathname.new(prefix).cleanpath.to_s.split("/").include?("..")
          return error_response("prefix must not contain '..' segments")
        end

        root = Rails.root
        docs_root = root.join("docs").cleanpath
        claude_md = root.join("CLAUDE.md").cleanpath

        # Glob inside docs/ honoring prefix + name_pattern. Recursive so
        # nested folders (plans/, decisions/, etc.) all surface.
        glob_root = docs_root.join(prefix)
        pattern = glob_root.join("**", name_pattern).to_s
        matches = Dir.glob(pattern).map { |p| Pathname.new(p).cleanpath }

        # Confine matches strictly to the docs tree even if a glob
        # somehow wandered (defensive — Dir.glob doesn't follow ".." but
        # we double-check).
        matches.select! { |p| p.file? && DevDocPath.inside?(p, docs_root) && p.extname == ".md" }

        # CLAUDE.md is included when prefix is empty AND it matches
        # name_pattern. The spec is explicit on this corner.
        if prefix.empty? && claude_md.file? && File.fnmatch?(name_pattern, claude_md.basename.to_s)
          matches << claude_md
        end

        matches.uniq!

        rows = matches.map { |path| row_for(path, root) }

        rows = case sort.to_s
        when "mtime_asc"  then rows.sort_by { |r| [ r[:_mtime], r[:path] ] }
        when "path"       then rows.sort_by { |r| r[:path] }
        else                   rows.sort_by { |r| [ -r[:_mtime], r[:path] ] }
        end

        rows = rows.first(limit)

        # Strip the internal sort key before serializing.
        data = rows.map { |r| r.except(:_mtime) }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end

      def self.row_for(path, root)
        stat = path.stat
        {
          path: path.relative_path_from(root).to_s,
          last_modified_at: stat.mtime.utc.iso8601,
          size_bytes: stat.size,
          first_heading: first_h1(path),
          _mtime: stat.mtime.to_f
        }
      end

      # First H1 line of a markdown file. Returns "" if the file has
      # no `# ` line. Reads line-by-line so very large files don't blow
      # memory; bails out at a sane scan cap.
      MAX_HEADING_SCAN_LINES = 200

      def self.first_h1(path)
        scanned = 0
        File.foreach(path) do |line|
          scanned += 1
          break if scanned > MAX_HEADING_SCAN_LINES
          if line.start_with?("# ") && !line.start_with?("## ")
            return line.sub(/\A#\s+/, "").chomp
          end
        end
        ""
      rescue StandardError
        ""
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
