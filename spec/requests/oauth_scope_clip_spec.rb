require "rails_helper"

# Phase 7.5 — Doorkeeper scope soft-clip.
#
# Verifies the intersection-based scope handling installed by
# `config/initializers/doorkeeper_scope_clip.rb`. Each example exercises
# the full Authorization Code + PKCE round-trip when validation should
# succeed, and asserts on the redirect / response status when validation
# should fail.
#
# Phase 10 — MCP scope simplification (ADR 0004). Catalog: `dev` + `app`.
# The clip math is catalog-agnostic; this spec re-verifies it under the
# new shape and adds explicit examples for the legacy 9-scope reject
# path and the strip-on-release production posture.
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
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: Scopes::DEV,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[authorize]")
    end

    it "renders the consent screen when app scopes = requested" do
      sign_in_as(user)
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: "#{Scopes::DEV} #{Scopes::APP}",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[authorize]")
    end

    it "renders the consent screen when requested ⊃ app scopes (clip case)" do
      sign_in_as(user)
      app = build_app(Scopes::DEV)

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
      app = build_app(Scopes::DEV)

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: Scopes::APP,
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
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: "#{Scopes::DEV} bogus:scope",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response.status).not_to eq(200)
      expect(response.body).not_to include("[authorize]")
    end

    it "rejects legacy 9-scope strings (e.g. 'dev:read') as out-of-catalog" do
      sign_in_as(user)
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: "dev:read",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response.status).not_to eq(200)
      expect(response.body).not_to include("[authorize]")
    end

    it "renders the consent screen for the Claude.ai-shaped 'dev app' request against an app declaring 'dev app'" do
      sign_in_as(user)
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: "#{Scopes::DEV} #{Scopes::APP}",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[authorize]")
    end
  end

  describe "POST /oauth/authorize → /oauth/token — issued scope intersection" do
    it "issues 'dev' alone when requested matches" do
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      body = authorize_and_exchange(app, Scopes::DEV)
      expect(body).to be_a(Hash)
      expect(body["scope"].to_s.split).to contain_exactly(Scopes::DEV)
    end

    it "issues 'app' alone when requested matches" do
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      body = authorize_and_exchange(app, Scopes::APP)
      expect(body).to be_a(Hash)
      expect(body["scope"].to_s.split).to contain_exactly(Scopes::APP)
    end

    it "issues 'dev app' when requested matches" do
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      body = authorize_and_exchange(app, "#{Scopes::DEV} #{Scopes::APP}")
      expect(body).to be_a(Hash)
      expect(body["scope"].to_s.split).to contain_exactly(Scopes::DEV, Scopes::APP)
    end

    it "clips to app.scopes when requested ⊃ app.scopes" do
      app = build_app(Scopes::DEV)

      body = authorize_and_exchange(app, Scopes::ALL.join(" "))
      expect(body).to be_a(Hash), "expected token response, got #{body.inspect}"
      expect(body["scope"].to_s.split).to contain_exactly(Scopes::DEV)
    end

    it "rejects when app.scopes ∩ requested = ∅" do
      app = build_app(Scopes::DEV)

      result = authorize_and_exchange(app, Scopes::APP)
      expect(result).to eq(:error_redirect)
    end

    it "rejects when a requested scope is outside the server catalog" do
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      result = authorize_and_exchange(app, "#{Scopes::DEV} bogus:scope")
      expect(result).to eq(:error_redirect)
    end

    it "clips legacy scope strings out (legacy 'dev:read' is rejected)" do
      app = build_app("#{Scopes::DEV} #{Scopes::APP}")

      result = authorize_and_exchange(app, "dev:read")
      expect(result).to eq(:error_redirect)
    end
  end

  describe "Phase 10 — strip-on-release (expose_dev_scope = false)" do
    it "rejects an authorize request for 'dev' when the server catalog excludes it" do
      original_server_scopes = Doorkeeper.config.scopes
      original_default_scopes = Doorkeeper.config.default_scopes
      original_flag = Rails.application.config.x.mcp.expose_dev_scope
      Rails.application.config.x.mcp.expose_dev_scope = false
      Doorkeeper.config.instance_variable_set(:@scopes, Doorkeeper::OAuth::Scopes.from_array([ Scopes::APP ]))
      Doorkeeper.config.instance_variable_set(:@default_scopes, Doorkeeper::OAuth::Scopes.from_array([ Scopes::APP ]))

      sign_in_as(user)
      # Application scope must already be in the (restricted) server
      # set; build the app with `app` only.
      app = build_app(Scopes::APP)

      get "/oauth/authorize", params: {
        response_type: "code",
        client_id: app.uid,
        redirect_uri: app.redirect_uri,
        scope: "dev",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      expect(response.status).not_to eq(200)
      expect(response.body).not_to include("[authorize]")
    ensure
      Rails.application.config.x.mcp.expose_dev_scope = original_flag
      Doorkeeper.config.instance_variable_set(:@scopes, original_server_scopes)
      Doorkeeper.config.instance_variable_set(:@default_scopes, original_default_scopes)
    end
  end
end
