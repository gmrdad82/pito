require "mcp"
require "mcp/server/transports/stdio_transport"
require_relative "tool_auth"

module Mcp
  class PitoServer
    INSTRUCTIONS = <<~TEXT.freeze
      You are connected to pito, a YouTube channel management and analytics tool.
      You can browse channels, videos, stats, search content, create/update/delete records,
      and view dashboard analytics. All data is real — treat it as the user's live workspace.
    TEXT

    def self.build
      server = MCP::Server.new(
        name: "pito",
        version: version,
        instructions: INSTRUCTIONS
      )

      register_tools(server)
      register_resources(server)

      server
    end

    def self.start_stdio
      server = build
      transport = MCP::Server::Transports::StdioTransport.new(server)
      transport.open
    end

    def self.version
      File.read(Rails.root.join("VERSION")).strip
    rescue Errno::ENOENT
      "0.0.0"
    end

    def self.register_tools(server)
      Dir[Rails.root.join("app/mcp/tools/*.rb")].sort.each { |f| require f }

      Tools.constants.filter_map { |c| Tools.const_get(c) }
        .select { |c| c.is_a?(Class) && c < MCP::Tool }
        .each { |tool| server.tools[tool.name_value] = tool }
    end

    def self.register_resources(server)
      Dir[Rails.root.join("app/mcp/resources/*.rb")].sort.each { |f| require f }

      resource_instances = Resources.constants.filter_map { |c| Resources.const_get(c) }
        .select { |c| c.respond_to?(:definitions) }
        .flat_map(&:definitions)

      resource_instances.each { |r| server.resources << r }

      server.resources_read_handler do |params|
        uri = params[:uri]
        handler = Resources.constants.filter_map { |c| Resources.const_get(c) }
          .select { |c| c.respond_to?(:read) }
          .find { |c| c.handles?(uri) }

        if handler
          handler.read(uri)
        else
          [ { uri: uri, mimeType: "text/plain", text: "resource not found: #{uri}" } ]
        end
      end
    end
  end
end
