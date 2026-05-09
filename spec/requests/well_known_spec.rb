require "rails_helper"

# Phase 7.5 — MCP OAuth discovery metadata.
#
# Two public, unauthenticated `/.well-known/...` endpoints used by
# Claude.ai's MCP custom connector to discover Pito's OAuth surface.
# Verified shape: status 200, JSON content-type, hardcoded `issuer` /
# `resource` URLs (NOT derived from `request.host` — they must remain
# stable whether the probe lands on `app.pitomd.com` or
# `mcp.pitomd.com`), and no auth chain involvement.
RSpec.describe "Well-known OAuth metadata", type: :request, unauthenticated: true do
  let(:json_headers) do
    { "Accept" => "application/json" }
  end

  describe "GET /.well-known/oauth-authorization-server" do
    it "returns RFC 8414 metadata as JSON without requiring auth" do
      get "/.well-known/oauth-authorization-server", headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      expect(body["issuer"]).to eq("https://app.pitomd.com")
      expect(body["authorization_endpoint"]).to eq("https://app.pitomd.com/oauth/authorize")
      expect(body["token_endpoint"]).to eq("https://app.pitomd.com/oauth/token")
      expect(body["revocation_endpoint"]).to eq("https://app.pitomd.com/oauth/revoke")
      expect(body["introspection_endpoint"]).to eq("https://app.pitomd.com/oauth/introspect")
      expect(body["response_types_supported"]).to eq([ "code" ])
      expect(body["grant_types_supported"]).to match_array(%w[authorization_code refresh_token])
      expect(body["code_challenge_methods_supported"]).to eq([ "S256" ])
      expect(body["token_endpoint_auth_methods_supported"]).to include("client_secret_basic", "client_secret_post")
      expect(body["scopes_supported"]).to match_array(Scopes::ALL)
      # Phase 7.5 — MCP custom-connector icon discovery. Non-standard
      # `logo_uri` extension; some clients honor it as a courtesy hint
      # for the connector-list icon.
      expect(body["logo_uri"]).to eq("https://app.pitomd.com/Pito.png")
    end

    it "does not redirect to /login (anonymous access path)" do
      # Sanity check the `allow_anonymous` declaration — the cookie-session
      # before_action would otherwise bounce unauthenticated callers.
      get "/.well-known/oauth-authorization-server"
      expect(response).not_to be_redirect
      expect(response).to have_http_status(:ok)
    end

    it "returns the same hardcoded issuer regardless of request host" do
      # Both subdomains route to the same Rails app; the metadata MUST
      # advertise `issuer: app.pitomd.com` even when probed via
      # `mcp.pitomd.com`, otherwise OAuth discovery breaks for clients
      # that probe both endpoints.
      get "/.well-known/oauth-authorization-server",
          headers: json_headers.merge("Host" => "mcp.pitomd.com")

      expect(JSON.parse(response.body)["issuer"]).to eq("https://app.pitomd.com")
    end
  end

  describe "GET /.well-known/oauth-protected-resource" do
    it "returns RFC 9728 metadata as JSON without requiring auth" do
      get "/.well-known/oauth-protected-resource", headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      body = JSON.parse(response.body)
      # Phase 7.5 connector hardening — `resource` advertises the
      # canonical MCP endpoint (`/mcp`), not just the host origin.
      # Clients that consult this metadata use the value verbatim as
      # the POST target.
      expect(body["resource"]).to eq("https://mcp.pitomd.com/mcp")
      expect(body["authorization_servers"]).to eq([ "https://app.pitomd.com" ])
      expect(body["bearer_methods_supported"]).to eq([ "header" ])
      expect(body["scopes_supported"]).to match_array(Scopes::ALL)
      # Phase 7.5 — MCP custom-connector icon discovery. Non-standard
      # `logo_uri` extension; mirror of the AS-metadata hint above.
      expect(body["logo_uri"]).to eq("https://app.pitomd.com/Pito.png")
    end

    it "does not redirect to /login (anonymous access path)" do
      get "/.well-known/oauth-protected-resource"
      expect(response).not_to be_redirect
      expect(response).to have_http_status(:ok)
    end

    it "returns the same hardcoded resource regardless of request host" do
      get "/.well-known/oauth-protected-resource",
          headers: json_headers.merge("Host" => "app.pitomd.com")

      expect(JSON.parse(response.body)["resource"]).to eq("https://mcp.pitomd.com/mcp")
    end
  end
end
