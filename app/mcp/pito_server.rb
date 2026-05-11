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

    # Phase 10 — strip-on-release. The three dev-KB tools (`list_docs`,
    # `read_doc`, `save_note`) are gated behind
    # `Rails.application.config.x.mcp.expose_dev_scope`. Production
    # builds set the flag to `false`, so the tools are NOT registered
    # and `tools/list` does not advertise them. Defense-in-depth pairs
    # with the per-tool `require_scope!(Scopes::DEV)` check inside
    # each tool — even if the flag is misconfigured at build time, a
    # call against the disabled scope still fails closed.
    DEV_TOOL_NAMES = %w[list_docs read_doc save_note].freeze

    # Phase 25 — 01d. Mirror the strip-on-release pattern for the `auth`
    # scope tools. The login-security MCP surface (pending listing,
    # approve / block / unblock / purge, audit log read) is gated behind
    # `Rails.application.config.x.mcp.expose_auth_scope`. Production
    # builds strip the scope from the catalog and the tools from the
    # registry; the per-tool `require_scope!(Scopes::AUTH)` check
    # provides defense-in-depth.
    AUTH_TOOL_NAMES = %w[
      login_attempts_pending
      login_attempts_list
      login_attempt_approve
      login_attempt_block
      login_attempt_unblock
      login_attempt_purge
      auth_audit_log_list
      blocked_locations_list
    ].freeze

    def self.register_tools(server)
      Dir[Rails.root.join("app/mcp/tools/*.rb")].sort.each { |f| require f }

      tools = Tools.constants.filter_map { |c| Tools.const_get(c) }
        .select { |c| c.is_a?(Class) && c < MCP::Tool }

      unless dev_scope_exposed?
        tools = tools.reject { |t| DEV_TOOL_NAMES.include?(t.name_value.to_s) }
      end

      unless auth_scope_exposed?
        tools = tools.reject { |t| AUTH_TOOL_NAMES.include?(t.name_value.to_s) }
      end

      tools.each { |tool| server.tools[tool.name_value] = tool }
    end

    def self.dev_scope_exposed?
      return true unless Rails.application.config.x.respond_to?(:mcp)
      flag = Rails.application.config.x.mcp&.expose_dev_scope
      flag.nil? ? true : flag
    end

    def self.auth_scope_exposed?
      return true unless Rails.application.config.x.respond_to?(:mcp)
      flag = Rails.application.config.x.mcp&.expose_auth_scope
      flag.nil? ? true : flag
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
