module Mcp
  module Tools
    class ReadDoc < MCP::Tool
      tool_name "read_doc"
      description "Read a single markdown file by repo-relative path. Path must end in .md and resolve to either CLAUDE.md or somewhere under docs/. Returns {path, content, last_modified_at}."

      input_schema(
        type: "object",
        properties: {
          path: { type: "string", description: "Repo-relative path, e.g. 'docs/design.md' or 'CLAUDE.md'" }
        },
        required: [ "path" ]
      )

      annotations(read_only_hint: true)

      def self.call(path:)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::DEV_READ)
        return scope_err if scope_err

        absolute = DevDocPath.resolve(path)

        unless absolute.file?
          return error_response("file not found: #{path}")
        end

        data = {
          path: absolute.relative_path_from(Rails.root).to_s,
          content: File.read(absolute),
          last_modified_at: absolute.stat.mtime.utc.iso8601
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      rescue DevDocPath::Error => e
        error_response(e.message)
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
