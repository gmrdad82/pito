module Mcp
  module Tools
    class CreateChannel < MCP::Tool
      tool_name "create_channel"
      description "Create a new channel from a canonical YouTube channel URL (https://www.youtube.com/channel/UC...). After creation, an initial sync is enqueued."

      EXAMPLE_URL = "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ".freeze

      input_schema(
        type: "object",
        properties: {
          channel_url: {
            type: "string",
            description: "Canonical channel URL, e.g. #{EXAMPLE_URL}"
          }
        },
        required: [ "channel_url" ]
      )

      annotations(read_only_hint: false)

      def self.call(channel_url:)
        url = channel_url.to_s.strip
        unless url.match?(Channel::CHANNEL_URL_REGEX)
          return error_response(
            "invalid channel_url. expected canonical YouTube channel URL like #{EXAMPLE_URL}"
          )
        end

        tenant_id = Current.tenant&.id || Tenant.first&.id
        if tenant_id.nil?
          return error_response("no tenant available — seed a Tenant first")
        end

        channel = Channel.new(channel_url: url, tenant_id: tenant_id)

        if channel.save
          data = ChannelDecorator.new(channel).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "channel created.\n#{JSON.pretty_generate(data)}" } ])
        else
          error_response("couldn't create channel: #{channel.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
