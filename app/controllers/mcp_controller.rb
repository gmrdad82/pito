# frozen_string_literal: true

# The MCP endpoint (G130) — POST /mcp, JSON-RPC 2.0 over MCP Streamable HTTP.
# READ-ONLY: every tool routes through Pito::Mcp::Executor, which never persists.
# Bearer-authenticated (OAuth, P4); no cookie session, so it is deliberately NOT an
# ApplicationController subclass (no session-auth concern). A dedicated Puma
# container serves this in production so a slow tool loop can't starve the app.
#
# Methods: initialize · notifications/initialized (a notification → 202, no body) ·
# tools/list · tools/call · ping. One-shot JSON responses — no SSE needed for these.
# JSON-RPC batching was removed in protocol 2025-06-18, so only single objects.
class McpController < ActionController::Base
  # No browser forms + no cookie session ⇒ CSRF is moot; the Bearer gate is the auth.
  skip_forgery_protection
  before_action :authenticate_mcp!

  PROTOCOL_VERSION = "2025-06-18"

  # A JSON-RPC error to surface with a specific code (parse/invalid/method/params).
  class RpcError < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def handle
    message = parse_message
    return head(:accepted) if notification?(message) # notifications get no response

    render json: success(message["id"], dispatch_rpc(message))
  rescue RpcError => e
    render json: failure(request_id, e.code, e.message)
  end

  private

  # ── JSON-RPC framing ─────────────────────────────────────────────────────────

  def parse_message
    parsed = JSON.parse(request.body.read.presence || "null")
    raise RpcError.new(-32600, "Invalid Request") unless parsed.is_a?(Hash)

    @request_id = parsed["id"]
    parsed
  rescue JSON::ParserError
    raise RpcError.new(-32700, "Parse error")
  end

  # A message with no `id` is a notification — no response is sent.
  def notification?(message)
    !message.key?("id")
  end

  def dispatch_rpc(message)
    case message["method"]
    when "initialize" then initialize_result
    when "tools/list" then { "tools" => Pito::Mcp::Registry.tools }
    when "tools/call" then tools_call(message["params"])
    when "ping"       then {}
    else raise RpcError.new(-32601, "Method not found: #{message['method']}")
    end
  end

  def tools_call(params)
    name = params.is_a?(Hash) ? params["name"] : nil
    raise RpcError.new(-32602, "Invalid params: missing tool name") if name.blank?

    result = Pito::Mcp::Executor.call(tool: name, arguments: params["arguments"] || {})
    { "content" => [ { "type" => "text", "text" => result.text } ], "isError" => result.is_error }
  rescue Pito::Mcp::Executor::UnknownTool
    raise RpcError.new(-32602, "Unknown tool: #{name}")
  end

  def initialize_result
    {
      "protocolVersion" => PROTOCOL_VERSION,
      "capabilities"    => { "tools" => {} },
      "serverInfo"      => { "name" => "pito", "version" => Pito::Version.suffix }
    }
  end

  def success(id, result)
    { jsonrpc: "2.0", id: id, result: result }
  end

  def failure(id, code, message)
    { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
  end

  def request_id
    defined?(@request_id) ? @request_id : nil
  end

  # ── Bearer gate (OAuth-backed in P4) ─────────────────────────────────────────

  def authenticate_mcp!
    @mcp_client = Pito::Mcp::Auth.authenticate(bearer_token)
    render_unauthorized if @mcp_client.nil?
  end

  def bearer_token
    request.headers["Authorization"].to_s[/\ABearer\s+(.+)\z/i, 1]
  end

  # 401 + the RFC 9728 discovery pointer so the client knows where to start OAuth.
  def render_unauthorized
    metadata_url = "#{request.base_url}/.well-known/oauth-protected-resource"
    response.headers["WWW-Authenticate"] = %(Bearer resource_metadata="#{metadata_url}")
    render json: failure(request_id, -32001, "Unauthorized"), status: :unauthorized
  end
end
