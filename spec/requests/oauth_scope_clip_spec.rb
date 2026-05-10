require "rails_helper"

# Phase 7.5 — Doorkeeper scope soft-clip.
#
# Verifies the intersection-based scope handling installed by
# `config/initializers/doorkeeper_scope_clip.rb`. Each example exercises
# the full Authorization Code + PKCE round-trip when validation should
# succeed, and asserts on the redirect / response status when validation
# should fail.
RSpec.describe "OAuth scope soft-clip", type: :request do
  let!(:user) { Current.user || create(:user) }

  let(:code_verifier)  { SecureRandom.urlsafe_base64(64) }
  let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }

  def build_app(app_scopes)
    create(
      :oauth_application,
      name: "scope-clip-test",
      redirect_uri: "http://127.0.0.1:8765/callback",
      scopes: app_scopes,
      confidential: false
    )
  end

  def authorize_and_exchange(application, requested_scope)
    sign_in_as(user)

    post "/oauth/authorize", params: {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      state: "abc",
      response_type: "code",
      scope: requested_scope,
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    return :pre_auth_failed unless response.status == 302

    location = response.location
    return :pre_auth_failed unless location.start_with?(application.redirect_uri)

    query = URI.parse(location).query.to_s
    if query.include?("error=")
      return :error_redirect
    end

    code = query.split("&").find { |kv| kv.start_with?("code=") }&.split("=", 2)&.last
    return :no_code unless code.present?

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      code: code,
      code_verifier: code_verifier
    }

    return :token_failed unless response.status == 200

    JSON.parse(response.body)
  end

  describe "GET /oauth/authorize — scope validation" do
    it "renders the consent screen when app scopes ⊃ requested" do
      sign_in_as(user)
      app = build_app("#{Scopes::DEV_READ} #{Scopes::DEV_WRITE} #{Scopes::PROJECT_READ}")

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: Scopes::DEV_READ,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[authorize]")
    end

    it "renders the consent screen when app scopes = requested" do
      sign_in_as(user)
      app = build_app("#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}")

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: "#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[authorize]")
    end

    it "renders the consent screen when requested ⊃ app scopes (clip case)" do
      sign_in_as(user)
      app = build_app("#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}")

      # Client requests every advertised scope (Claude.ai shape).
      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: Scopes::ALL.join(" "),
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[authorize]")
    end

    it "rejects with invalid_scope when app scopes ∩ requested = ∅" do
      sign_in_as(user)
      app = build_app(Scopes::DEV_READ)

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: Scopes::PROJECT_WRITE,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      # Doorkeeper redirects with an `error=invalid_scope` query string
      # when the redirect_uri is valid; the consent page is NOT rendered.
      expect(response.status).not_to eq(200)
      expect(response.body).not_to include("[authorize]")
    end

    it "rejects with invalid_scope when a requested scope is outside the server catalog" do
      sign_in_as(user)
      app = build_app("#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}")

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: "#{Scopes::DEV_READ} bogus:scope",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response.status).not_to eq(200)
      expect(response.body).not_to include("[authorize]")
    end
  end

  describe "POST /oauth/authorize → /oauth/token — issued scope intersection" do
    it "issues the requested scopes when app scopes ⊃ requested" do
      app = build_app("#{Scopes::DEV_READ} #{Scopes::DEV_WRITE} #{Scopes::PROJECT_READ}")

      body = authorize_and_exchange(app, Scopes::DEV_READ)
      expect(body).to be_a(Hash)
      expect(body["scope"].to_s.split).to contain_exactly(Scopes::DEV_READ)
    end

    it "issues the requested scopes when app scopes = requested" do
      app = build_app("#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}")

      body = authorize_and_exchange(app, "#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}")
      expect(body).to be_a(Hash)
      expect(body["scope"].to_s.split).to contain_exactly(Scopes::DEV_READ, Scopes::PROJECT_READ)
    end

    it "clips to app.scopes when requested ⊃ app.scopes" do
      app = build_app("#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}")

      body = authorize_and_exchange(app, Scopes::ALL.join(" "))
      expect(body).to be_a(Hash), "expected token response, got #{body.inspect}"
      expect(body["scope"].to_s.split).to contain_exactly(Scopes::DEV_READ, Scopes::PROJECT_READ)
    end

    it "rejects when app.scopes ∩ requested = ∅" do
      app = build_app(Scopes::DEV_READ)

      result = authorize_and_exchange(app, Scopes::PROJECT_WRITE)
      expect(result).to eq(:error_redirect)
    end

    it "rejects when a requested scope is outside the server catalog" do
      app = build_app("#{Scopes::DEV_READ} #{Scopes::PROJECT_READ}")

      result = authorize_and_exchange(app, "#{Scopes::DEV_READ} bogus:scope")
      expect(result).to eq(:error_redirect)
    end
  end
end
