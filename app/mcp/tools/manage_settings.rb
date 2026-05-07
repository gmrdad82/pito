module Mcp
  module Tools
    class ManageSettings < MCP::Tool
      tool_name "manage_settings"
      description "View or update app settings (max_panes, pane_title_length, theme). Call with no arguments to view current settings."

      ALLOWED_KEYS = %w[max_panes pane_title_length theme].freeze

      input_schema(
        type: "object",
        properties: {
          updates: {
            type: "object",
            description: "Key-value pairs to update. Allowed keys: max_panes, pane_title_length, theme (light/dark/auto)",
            additionalProperties: { type: "string" }
          }
        },
      )

      def self.call(updates: nil)
        # Read with no args needs yt:read; mutating call needs yt:write.
        required = updates.present? ? Scopes::YT_WRITE : Scopes::YT_READ
        scope_err = Mcp::ToolAuth.require_scope!(required)
        return scope_err if scope_err

        if updates.present?
          results = []
          updates.each do |key, value|
            key = key.to_s
            unless ALLOWED_KEYS.include?(key)
              results << "skipped unknown key: #{key}"
              next
            end
            if key == "theme" && !%w[light dark auto].include?(value)
              results << "invalid theme: #{value} (must be light, dark, or auto)"
              next
            end
            AppSetting.set(key, value)
            results << "#{key} = #{value}"
          end
          MCP::Tool::Response.new([ { type: "text", text: "settings updated.\n#{results.join("\n")}" } ])
        else
          current = ALLOWED_KEYS.map { |k| "#{k}: #{AppSetting.get(k) || '(default)'}" }
          MCP::Tool::Response.new([ { type: "text", text: current.join("\n") } ])
        end
      end
    end
  end
end
