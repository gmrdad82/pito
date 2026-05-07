# Phase 3 — Step B (5b-token-and-auth-concern.md) — token context for specs.
#
# `Mcp::ToolAuth` is required by every tool's `call` method. Tool specs
# load tools via `require_relative` and don't go through `PitoServer`,
# so we eager-load the helper here.
require Rails.root.join("app/mcp/tool_auth")

#
# MCP tool specs call `Mcp::Tools::*.call(...)` directly, bypassing the
# Rack auth path. Now that every tool calls `Mcp::ToolAuth.require_scope!`,
# tools rejected the call when `Current.token` was nil. Tool specs are
# functional unit tests; the auth surface is exercised separately
# (`spec/lib/api/token_authenticator_spec.rb`,
#  `spec/requests/mcp/rack_app_auth_spec.rb`).
#
# This helper installs a `before(:each)` hook for `type: :mcp` (and a few
# adjacent contexts) that builds a fully-scoped `ApiToken` and pins it
# on `Current.token`. Specs that need to assert per-scope rejection
# override `Current.token` inside the example.
#
# Note the lifecycle ordering: `tenant_context.rb` already runs
# `Current.tenant ||= ...` for non-HTTP specs, so by the time we land
# here, the tenant exists. We just pin a token that the tools can read
# scopes from.

# Default token covers every catalog scope so tool specs run with full
# permission unless they opt into a narrower scope set. The token is
# memoized per example via `Current.token =` so it resets cleanly via
# the `Current.reset` after-hook in `rails_helper.rb`.
SCOPED_TOOL_SPEC_TYPES = %i[mcp].freeze

# Match by file path too, since tool specs may not declare `type: :mcp`
# explicitly. Anything under `spec/mcp/` counts.
def __pito_tool_spec?(example)
  return true if SCOPED_TOOL_SPEC_TYPES.include?(example.metadata[:type])

  file_path = example.metadata[:file_path].to_s
  file_path.include?("/spec/mcp/")
end

RSpec.configure do |config|
  config.before(:each) do |example|
    next unless __pito_tool_spec?(example)

    tenant = Current.tenant || (Current.tenant = Tenant.first || FactoryBot.create(:tenant))
    user   = Current.user   || (Current.user   = User.first  || FactoryBot.create(:user, tenant: tenant))

    record, _plaintext = ApiToken.generate!(
      tenant: tenant,
      user: user,
      name: "spec-token-#{rand(1_000_000)}",
      scopes: Scopes::ALL.dup
    )
    Current.token = record
  end
end
