module Mcp
  module Tools
    class GetDashboard < MCP::Tool
      tool_name "get_dashboard"
      description "Get dashboard status counts: videos, channels, projects, footages, notes. Chart-sweep dispatch (2026-05-07): chart payloads (daily views, views by channel, daily engagement) are retired pending intentional metrics in a later phase."

      input_schema(type: "object", properties: {})

      annotations(read_only_hint: true)

      def self.call
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::YT_READ)
        return scope_err if scope_err

        data = {
          video_count: Video.count,
          channel_count: Channel.count,
          project_count: Project.count,
          footage_count: Footage.count,
          note_count: Note.count
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end
    end
  end
end
