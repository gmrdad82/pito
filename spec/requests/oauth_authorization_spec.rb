require "rails_helper"

# Phase 12 — Step B (6b-doorkeeper-oauth-server.md). End-to-end smoke
# test of the Doorkeeper authorization endpoint. The full Authorization
# Code + PKCE round-trip is exercised via direct controller hits — the
# CLI client side (loopback handler that catches the redirect) is a
# follow-up, not part of this step's spec.
RSpec.describe "OAuth authorization", type: :request do
  let!(:user) { Current.user || create(:user, tenant: Current.tenant) }
  let!(:application) do
    create(
      :oauth_application,
      tenant: Current.tenant,
      name: "test-cli",
      redirect_uri: "http://127.0.0.1:8765/callback",
      scopes: "#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}",
      confidential: false
    )
  end

  let(:code_verifier)  { SecureRandom.urlsafe_base64(64) }
  let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }

  describe "GET /oauth/authorize", :unauthenticated do
    it "redirects to /login when no session cookie is set" do
      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: application.uid,
        redirect_uri: application.redirect_uri,
        scope: Scopes::DEV_READ,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(login_path)
    end
  end

  describe "GET /oauth/authorize" do
    it "renders the consent screen when authenticated" do
      sign_in_as(user)
      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: application.uid,
        redirect_uri: application.redirect_uri,
        scope: Scopes::DEV_READ,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[authorize]")
      expect(response.body).to include(application.name)
    end

    # Phase 7.5 connector hardening — the consent page must render
    # inside Pito's `application` layout, not Doorkeeper's bundled
    # `doorkeeper/application` layout. We verify three layout markers
    # that ONLY exist in Pito's layout: the `data-theme-preference`
    # html-tag attribute, the page title's `~ pito` suffix, and the
    # `application-name` meta tag. If any of these are missing we are
    # back to Doorkeeper's bundled chrome.
    #
    # See `config/initializers/doorkeeper_layout.rb`.
    it "renders inside Pito's application layout (data-theme-preference + title + meta)" do
      sign_in_as(user)
      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: application.uid,
        redirect_uri: application.redirect_uri,
        scope: Scopes::DEV_READ,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-theme-preference=")
      expect(response.body).to match(/<title>[^<]*~ pito<\/title>/)
      expect(response.body).to include('<meta name="application-name" content="Pito">')
    end

    it "rejects an authorization request without PKCE for a public client" do
      sign_in_as(user)
      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: application.uid,
        redirect_uri: application.redirect_uri,
        scope: Scopes::DEV_READ
      }
      # Doorkeeper's force_pkce returns either a redirect with error
      # query string or renders an error page. Both are non-200; we
      # accept any non-2xx as evidence that PKCE was enforced.
      expect(response.status).not_to eq(200)
    end
  end

  describe "Authorization Code + PKCE round trip" do
    it "issues a code, exchanges it for a token, and the refresh rotates" do
      sign_in_as(user)

      post "/oauth/authorize", params: {
        client_id: application.uid,
        redirect_uri: application.redirect_uri,
        state: "abc",
        response_type: "code",
        scope: Scopes::DEV_READ,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response).to have_http_status(:found)
      location = response.location
      expect(location).to start_with(application.redirect_uri)

      code = URI.parse(location).query.split("&").find { |kv| kv.start_with?("code=") }&.split("=", 2)&.last
      expect(code).to be_present, "expected the redirect to carry a code: #{location}"

      # Exchange the code for tokens.
      post "/oauth/token", params: {
        grant_type: "authorization_code",
        client_id: application.uid,
        redirect_uri: application.redirect_uri,
        code: code,
        code_verifier: code_verifier
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
      expect(body["expires_in"]).to eq(2.hours.to_i)

      original_refresh = body["refresh_token"]
      original_access  = body["access_token"]

      # Refresh — should rotate the refresh token.
      post "/oauth/token", params: {
        grant_type: "refresh_token",
        client_id: application.uid,
        refresh_token: original_refresh
      }

      expect(response).to have_http_status(:ok)
      refreshed_body = JSON.parse(response.body)
      expect(refreshed_body["access_token"]).not_to eq(original_access)
      expect(refreshed_body["refresh_token"]).not_to eq(original_refresh)

      # Revoke the access token.
      post "/oauth/revoke", params: {
        token: refreshed_body["access_token"],
        client_id: application.uid
      }
      expect(response).to have_http_status(:ok)
    end
  end
end
