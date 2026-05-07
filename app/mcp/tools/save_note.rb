module Mcp
  module Tools
    class SaveNote < MCP::Tool
      tool_name "save_note"
      description "Append a timestamped markdown note to docs/notes/. Server generates the filename: <YYYY-MM-DD-HH-MM-SS>-<slug>.md (UTC). The slug is sanitized to [a-z0-9-]; if it sanitizes to empty, falls back to 'note'. Sub-second collisions get a -2/-3 suffix. Returns {path, saved_at}."

      MAX_SLUG_LENGTH = 50
      WRITE_DIR = "docs/notes".freeze

      input_schema(
        type: "object",
        properties: {
          content: { type: "string", description: "Markdown body. Written verbatim — bytes in, bytes on disk." },
          slug:    { type: "string", description: "Optional filename hint, sanitized to [a-z0-9-]" }
        },
        required: [ "content" ]
      )

      annotations(read_only_hint: false)

      def self.call(content:, slug: nil)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::DEV_WRITE)
        return scope_err if scope_err

        if content.nil? || content.to_s.empty?
          return error_response("content is required")
        end

        clean_slug = sanitize_slug(slug)
        timestamp = Time.now.utc.strftime("%Y-%m-%d-%H-%M-%S")

        write_dir = Rails.root.join(WRITE_DIR)
        FileUtils.mkdir_p(write_dir)

        absolute = unique_path(write_dir, timestamp, clean_slug)
        File.write(absolute, content.to_s)

        data = {
          path: absolute.relative_path_from(Rails.root).to_s,
          saved_at: absolute.stat.mtime.utc.iso8601
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end

      # Sanitize the user-supplied slug to a safe filename component.
      #   - lowercase
      #   - spaces collapse to single hyphens
      #   - drop everything outside [a-z0-9-]
      #   - collapse runs of hyphens, strip leading/trailing hyphens
      #   - cap at MAX_SLUG_LENGTH characters
      #   - empty result falls back to "note"
      def self.sanitize_slug(raw)
        return "note" if raw.nil?
        s = raw.to_s.downcase
        s = s.gsub(/\s+/, "-")
        s = s.gsub(/[^a-z0-9-]/, "")
        s = s.gsub(/-+/, "-")
        s = s.gsub(/\A-+|-+\z/, "")
        s = s[0, MAX_SLUG_LENGTH]
        s.empty? ? "note" : s
      end

      # Append -2, -3, ... before .md if a file with the bare filename
      # already exists (sub-second collisions on concurrent saves).
      def self.unique_path(dir, timestamp, slug)
        base = "#{timestamp}-#{slug}"
        candidate = dir.join("#{base}.md")
        return candidate unless candidate.exist?

        suffix = 2
        loop do
          candidate = dir.join("#{base}-#{suffix}.md")
          return candidate unless candidate.exist?
          suffix += 1
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
