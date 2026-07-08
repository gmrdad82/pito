# frozen_string_literal: true

require "rails_helper"

# Request spec for the hand-rolled OAuth 2.1 endpoints (G130). Exercises the full
# browser + server flow: dynamic registration → consent (TOTP) → code → token
# exchange (PKCE S256) → refresh, plus the discovery documents. TOTP verification
# is stubbed (the real ROTP path is TotpVerifier's own spec).
RSpec.describe "OAuth endpoints", type: :request do
  let(:redirect_uri) { "https://claude.ai/callback" }
  let(:client)       { OauthClient.register(name: "claude.ai", redirect_uris: [ redirect_uri ]) }

  # A fresh PKCE verifier/challenge pair.
  let(:verifier)  { SecureRandom.urlsafe_base64(48) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }

  def authorize_params(overrides = {})
    {
      client_id: client.client_id, redirect_uri: redirect_uri, response_type: "code",
      code_challenge: challenge, code_challenge_method: "S256", state: "xyz"
    }.merge(overrides)
  end

  # ── discovery ──────────────────────────────────────────────────────────────
  describe "GET /.well-known/oauth-authorization-server" do
    it "advertises the endpoints, PKCE S256, and public-client auth" do
      get "/.well-known/oauth-authorization-server"
      body = response.parsed_body
      expect(body["authorization_endpoint"]).to end_with("/oauth/authorize")
      expect(body["token_endpoint"]).to end_with("/oauth/token")
      expect(body["registration_endpoint"]).to end_with("/oauth/register")
      expect(body["code_challenge_methods_supported"]).to eq(%w[S256])
      expect(body["token_endpoint_auth_methods_supported"]).to eq(%w[none])
    end
  end

  describe "GET /.well-known/oauth-protected-resource" do
    it "names this host as its own authorization server" do
      get "/.well-known/oauth-protected-resource"
      body = response.parsed_body
      expect(body["resource"]).to be_present
      expect(body["authorization_servers"]).to eq([ body["resource"] ])
    end
  end

  # ── registration (RFC 7591) ────────────────────────────────────────────────
  describe "POST /oauth/register" do
    def register(payload)
      post "/oauth/register", params: payload.to_json, headers: { "Content-Type" => "application/json" }
    end

    it "registers a public client and returns a client_id (no secret)" do
      register(client_name: "claude.ai", redirect_uris: [ redirect_uri ])
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["client_id"]).to be_present
      expect(body).not_to have_key("client_secret")
      expect(body["token_endpoint_auth_method"]).to eq("none")
    end

    it "rejects a non-https redirect URI" do
      register(client_name: "x", redirect_uris: [ "http://evil.example/cb" ])
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects an empty redirect list" do
      register(client_name: "x", redirect_uris: [])
      expect(response).to have_http_status(:bad_request)
    end
  end

  # ── authorize (consent) ────────────────────────────────────────────────────
  describe "GET /oauth/authorize" do
    it "renders the consent page with the client name and read-only scope" do
      get "/oauth/authorize", params: authorize_params
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("claude.ai", "read-only", "totp_code")
    end

    it "shows an on-page error (no redirect) for an unknown client" do
      get "/oauth/authorize", params: authorize_params(client_id: "nope")
      expect(response).to have_http_status(:bad_request)
      expect(response).not_to be_redirect
    end

    it "shows an on-page error (no redirect) for an unregistered redirect URI" do
      get "/oauth/authorize", params: authorize_params(redirect_uri: "https://evil.example/cb")
      expect(response).to have_http_status(:bad_request)
      expect(response).not_to be_redirect
    end

    it "redirects back with error=invalid_request when PKCE is missing" do
      get "/oauth/authorize", params: authorize_params(code_challenge: "")
      expect(response).to redirect_to(a_string_including("error=invalid_request"))
    end

    it "redirects back with error=unsupported_response_type for a non-code type" do
      get "/oauth/authorize", params: authorize_params(response_type: "token")
      expect(response).to redirect_to(a_string_including("error=unsupported_response_type"))
    end
  end

  # ── approve (TOTP consent → code) ──────────────────────────────────────────
  describe "POST /oauth/authorize (approve)" do
    it "mints a code and redirects back with code + state on a valid TOTP" do
      allow(Pito::Auth::TotpVerifier).to receive(:call).and_return(:ok)
      post "/oauth/authorize", params: authorize_params(totp_code: "123456")

      expect(response).to be_redirect
      location = URI.parse(response.location)
      expect(location.host).to eq("claude.ai")
      query = Rack::Utils.parse_query(location.query)
      expect(query["code"]).to be_present
      expect(query["state"]).to eq("xyz")
    end

    it "re-renders with an error and mints NO code on a wrong TOTP" do
      allow(Pito::Auth::TotpVerifier).to receive(:call).and_return(:invalid)
      expect do
        post "/oauth/authorize", params: authorize_params(totp_code: "000000")
      end.not_to change(OauthCode, :count)
      expect(response).to have_http_status(:unauthorized)
      expect(response).not_to be_redirect
    end
  end

  # ── token exchange (PKCE S256 + refresh) ───────────────────────────────────
  describe "POST /oauth/token" do
    # Drive a real code through consent, then return the raw code.
    def mint_code_via_consent
      allow(Pito::Auth::TotpVerifier).to receive(:call).and_return(:ok)
      post "/oauth/authorize", params: authorize_params(totp_code: "123456")
      Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
    end

    it "exchanges a code + verifier for an access + refresh token" do
      code = mint_code_via_consent
      post "/oauth/token", params: { grant_type: "authorization_code", code: code,
                                     redirect_uri: redirect_uri, client_id: client.client_id,
                                     code_verifier: verifier }
      body = response.parsed_body
      expect(body["token_type"]).to eq("Bearer")
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
      expect(body["expires_in"]).to be > 0
    end

    it "rejects a bad PKCE verifier (invalid_grant)" do
      code = mint_code_via_consent
      post "/oauth/token", params: { grant_type: "authorization_code", code: code,
                                     redirect_uri: redirect_uri, client_id: client.client_id,
                                     code_verifier: "wrong-verifier" }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_grant")
    end

    it "rejects a replayed (already-used) code" do
      code = mint_code_via_consent
      params = { grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
                 client_id: client.client_id, code_verifier: verifier }
      post "/oauth/token", params: params
      post "/oauth/token", params: params # replay
      expect(response.parsed_body["error"]).to eq("invalid_grant")
    end

    it "issues a fresh access token from a refresh grant" do
      code = mint_code_via_consent
      post "/oauth/token", params: { grant_type: "authorization_code", code: code,
                                     redirect_uri: redirect_uri, client_id: client.client_id, code_verifier: verifier }
      refresh = response.parsed_body["refresh_token"]

      post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: refresh }
      expect(response.parsed_body["access_token"]).to be_present
      expect(Pito::Mcp::Auth.authenticate(response.parsed_body["access_token"])).to be_present
    end

    it "rejects an unknown refresh token" do
      post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: "nope" }
      expect(response.parsed_body["error"]).to eq("invalid_grant")
    end

    it "rejects an unsupported grant type" do
      post "/oauth/token", params: { grant_type: "password" }
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("unsupported_grant_type")
    end
  end
end
