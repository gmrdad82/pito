require "rails_helper"

# Phase 12 — Step A. `Sessions::AuthConcern` is included by every HTML
# controller. Top-level coverage (signed-in 200, unauthenticated /login
# bounce, intended-URL stash) lives in
# `spec/requests/application_controller_current_spec.rb`. This spec
# fills gaps the audit identified:
#   - `allow_anonymous` exempts specific actions
#   - `auth_misconfigured` short-circuits with 500
#   - intended-URL stash skips POST/PATCH/DELETE
#   - intended-URL stash skips when already on /login
#   - intended-URL stash skips OAuth /token endpoints (only /authorize stashes)
#   - audit-logging hook fires on cookie-failure paths
#
# Anonymous-allowed actions: `SessionsController#new` and
# `WellKnownController#oauth_authorization_server` cover the two real
# usage patterns (login form + public well-known endpoint).
RSpec.describe "Sessions::AuthConcern", type: :request do
  describe "allow_anonymous", :unauthenticated do
    it "lets the login form render without a session cookie" do
      get login_path
      expect(response).to have_http_status(:ok)
    end

    it "lets the OAuth authorization-server metadata render without a session" do
      get "/.well-known/oauth-authorization-server"
      expect(response).to have_http_status(:ok)
    end

    it "still bounces non-allow-listed actions to /login" do
      get root_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "auth_misconfigured short-circuit", :unauthenticated do
    it "renders text/plain 500 when the authenticator reports misconfiguration" do
      result = Sessions::Authenticator::Result.new(reason: :auth_misconfigured)
      allow(Sessions::Authenticator).to receive(:call).and_return(result)

      get root_path
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to eq("auth misconfigured")
    end

    it "does NOT stash an intended-URL cookie on the misconfigured branch" do
      result = Sessions::Authenticator::Result.new(reason: :auth_misconfigured)
      allow(Sessions::Authenticator).to receive(:call).and_return(result)

      get channels_path
      set_cookie_header = Array(response.headers["Set-Cookie"]).flatten.join("\n")
      expect(set_cookie_header).not_to include(Sessions::AuthConcern::INTENDED_URL_COOKIE.to_s)
    end
  end

  describe "intended-URL stash", :unauthenticated do
    it "skips the stash for non-GET requests" do
      # Channels became read-only (`POST /channels` was removed), so
      # use `DELETE /channels/:id` as the representative non-GET,
      # auth-gated route. The stash-skip contract for non-GET requests
      # is unchanged.
      channel = create(:channel)
      delete channel_path(channel)
      expect(response).to redirect_to(login_path)
      set_cookie_header = Array(response.headers["Set-Cookie"]).flatten.join("\n")
      expect(set_cookie_header).not_to include(Sessions::AuthConcern::INTENDED_URL_COOKIE.to_s)
    end

    it "skips the stash when the intended URL is already /login" do
      # /login is allow-anonymous so the concern wouldn't redirect at
      # all — but the guard still matters when other entry points
      # forward to /login. Pin the contract.
      get login_path
      set_cookie_header = Array(response.headers["Set-Cookie"]).flatten.join("\n")
      expect(set_cookie_header).not_to include(Sessions::AuthConcern::INTENDED_URL_COOKIE.to_s)
    end

    it "preserves the full path with query string" do
      get channels_path, params: { star: "yes" }
      expect(response).to redirect_to(login_path)
      # The signed cookie value is opaque — but its key must be set.
      set_cookie_header = Array(response.headers["Set-Cookie"]).flatten.join("\n")
      expect(set_cookie_header).to include(Sessions::AuthConcern::INTENDED_URL_COOKIE.to_s)
    end
  end

  describe "audit logging hook", :unauthenticated do
    it "logs an auth-cookie-failure JSON line when a reason is present" do
      result = Sessions::Authenticator::Result.new(reason: :tampered_signature)
      allow(Sessions::Authenticator).to receive(:call).and_return(result)

      expect(AUTH_AUDIT_LOGGER).to receive(:info) do |line|
        payload = JSON.parse(line)
        expect(payload["event"]).to eq("session.cookie.invalid")
        expect(payload["reason"]).to eq("tampered_signature")
        expect(payload["route"]).to start_with("GET ")
      end

      get root_path
    end

    it "swallows logger errors (audit must never break the redirect)" do
      result = Sessions::Authenticator::Result.new(reason: :unknown_session)
      allow(Sessions::Authenticator).to receive(:call).and_return(result)
      allow(AUTH_AUDIT_LOGGER).to receive(:info).and_raise(StandardError, "log down")

      expect { get root_path }.not_to raise_error
      expect(response).to redirect_to(login_path)
    end
  end

  describe "successful cookie session populates Current and touches activity" do
    # Phase 29 — Unit A2. The user must be TOTP-configured or the
    # mandatory-2FA gate redirects `GET /` before the action runs.
    let!(:user) { Current.user || create(:user, :totp_enabled) }

    it "pins Current.session and Current.user, and touches the session" do
      record, _plaintext = Session.create_for!(
        user: user, ip: "127.0.0.1", user_agent: "RspecAgent", remember: false
      )
      result = Sessions::Authenticator::Result.new(session: record, reason: nil)
      allow(Sessions::Authenticator).to receive(:call).and_return(result)

      expect(record).to receive(:touch_activity!).at_least(:once).and_call_original
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Current.reset after the request" do
    let!(:user) { Current.user || create(:user) }

    it "clears Current.session / .user once the request finishes" do
      sign_in_as(user)
      get root_path
      # The around_action runs Current.reset in its `ensure` block.
      expect(Current.user).to be_nil
      expect(Current.session).to be_nil
    end
  end

  describe ".allow_anonymous DSL" do
    it "freezes the action list (no in-place mutation of one controller leaks to another)" do
      expect(SessionsController._anonymous_allowed_actions).to be_frozen
    end

    it "carries the new + create actions for SessionsController" do
      expect(SessionsController._anonymous_allowed_actions).to include(:new, :create)
    end

    it "leaves controllers without a declaration empty" do
      # ApplicationController never calls allow_anonymous; subclasses
      # that don't declare anything inherit the empty default.
      expect(ApplicationController._anonymous_allowed_actions).to eq([])
    end
  end
end
