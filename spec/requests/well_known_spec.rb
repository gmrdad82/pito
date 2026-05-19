require "rails_helper"

# Phase 7.5 — OAuth discovery metadata.
#
# Public, unauthenticated `/.well-known/oauth-authorization-server`
# endpoint used by Doorkeeper-aware OAuth clients to discover Pito's
# OAuth surface. Verified shape: status 200, JSON content-type,
# hardcoded `issuer` URL (NOT derived from `request.host` — it must
# remain stable whether the probe lands on `app.pitomd.com` or any
# other host), and no auth chain involvement.
#
# Phase 29 (MCP cut, 2026-05-19) — the `oauth-protected-resource`
# endpoint was removed alongside the MCP surface.
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
      # Non-standard `logo_uri` extension; some clients honor it as a
      # courtesy hint for the connector-list icon.
      expect(body["logo_uri"]).to eq("https://app.pitomd.com/android-chrome-192x192.png?v=2")
    end

    it "does not redirect to /login (anonymous access path)" do
      # Sanity check the `allow_anonymous` declaration — the cookie-session
      # before_action would otherwise bounce unauthenticated callers.
      get "/.well-known/oauth-authorization-server"
      expect(response).not_to be_redirect
      expect(response).to have_http_status(:ok)
    end

    it "returns the same hardcoded issuer regardless of request host" do
      # The metadata MUST advertise `issuer: app.pitomd.com` regardless
      # of which host the request landed on so OAuth discovery remains
      # stable across any future host plumbing.
      get "/.well-known/oauth-authorization-server",
          headers: json_headers.merge("Host" => "example.com")

      expect(JSON.parse(response.body)["issuer"]).to eq("https://app.pitomd.com")
    end
  end
end
