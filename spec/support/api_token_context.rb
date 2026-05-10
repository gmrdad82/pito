# Phase 3 — Step B (5b-token-and-auth-concern.md) — token context for specs.
#
# `Mcp::ToolAuth` is required by every tool's `call` method. Tool specs
# load tools via `require_relative` and don't go through `PitoServer`,
# so we eager-load the helper here.
require Rails.root.join("app/mcp/tool_auth")

# MCP tool specs call `Mcp::Tools::*.call(...)` directly, bypassing the
# Rack auth path. Now that every tool calls `Mcp::ToolAuth.require_scope!`,
# tools rejected the call when `Current.token` was nil. Tool specs are
# functional unit tests; the auth surface is exercised separately
# (`spec/lib/api/token_authenticator_spec.rb`,
#  `spec/requests/mcp/rack_app_auth_spec.rb`).
#
# Phase 8 — tenant drop. Tokens no longer carry a tenant; the helper
# just pins a fully-scoped token on `Current.token`.

SCOPED_TOOL_SPEC_TYPES = %i[mcp].freeze

def __pito_tool_spec?(example)
  return true if SCOPED_TOOL_SPEC_TYPES.include?(example.metadata[:type])

  file_path = example.metadata[:file_path].to_s
  file_path.include?("/spec/mcp/")
end

RSpec.configure do |config|
  config.before(:each) do |example|
    next unless __pito_tool_spec?(example)

    user = Current.user || (Current.user = User.first || FactoryBot.create(:user))

    record, _plaintext = ApiToken.generate!(
      user: user,
      name: "spec-token-#{rand(1_000_000)}",
      scopes: Scopes::ALL.dup
    )
    Current.token = record
  end
end
