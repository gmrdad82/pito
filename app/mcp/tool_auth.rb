# Phase 3 — Step B (5b-token-and-auth-concern.md) — MCP tool scope check.
#
# Helper used by every `Mcp::Tools::*.call` to assert the current bearer
# token carries the required scope. Returns either `nil` (proceed) or an
# `MCP::Tool::Response` with `error: true` (which the MCP gem renders as a
# tool-call error).
#
# Why a Response instead of a raise: the MCP gem's tool dispatch path
# wraps tool calls in its own rescuer, but the spec wants a clean
# "insufficient_scope" envelope back to the client. Returning an error
# Response keeps the wire shape predictable.
#
# Usage:
#   def self.call(...)
#     err = Mcp::ToolAuth.require_scope!(Scopes::DEV_READ)
#     return err if err
#     ...
#   end
module Mcp
  module ToolAuth
    module_function

    def require_scope!(scope)
      token = Current.token
      unless token && Array(token.scopes).include?(scope.to_s)
        return error_response(scope)
      end
      nil
    end

    def error_response(scope)
      payload = { error: "insufficient_scope", required: scope.to_s }
      MCP::Tool::Response.new(
        [ { type: "text", text: payload.to_json } ],
        error: true
      )
    end
  end
end
