# Phase 7.5 — MCP OAuth metadata. Canonical absolute base URLs for the
# Pito web Puma (`app.pitomd.com`) and the Pito MCP Puma
# (`mcp.pitomd.com`). The two hosts are stable across environments —
# both production and the dev Cloudflare tunnel terminate on the same
# names — so the OAuth metadata documents (`/.well-known/...`) can
# hardcode them without consulting `request.host`.
#
# Why hardcode (not derive from `request.host`): both subdomains route
# to the same Rails app, but the OAuth metadata MUST advertise:
#   - issuer = the authorization-server origin (`app.pitomd.com`)
#   - resource = the protected-resource origin (`mcp.pitomd.com`)
# regardless of which subdomain the request happened to land on. A
# request to `https://mcp.pitomd.com/.well-known/oauth-authorization-server`
# must still report `issuer: https://app.pitomd.com`, otherwise Claude
# clients that probe both endpoints get inconsistent issuer values and
# the OAuth dance breaks.
#
# Override knobs (test-only): `ENV["PITO_APP_BASE_URL"]` /
# `ENV["PITO_MCP_BASE_URL"]` let request specs and CI environments
# replace the canonical hosts without touching the constants.
module Pito
  module PublicHosts
    DEFAULT_APP_BASE = "https://app.pitomd.com"
    DEFAULT_MCP_BASE = "https://mcp.pitomd.com"

    module_function

    def app_base
      ENV.fetch("PITO_APP_BASE_URL", DEFAULT_APP_BASE).chomp("/")
    end

    def mcp_base
      ENV.fetch("PITO_MCP_BASE_URL", DEFAULT_MCP_BASE).chomp("/")
    end
  end
end
