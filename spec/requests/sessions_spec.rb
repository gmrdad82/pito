require "rails_helper"

# Phase 8 — Tenant Drop + Email-Only Login. The login form posts
# `email` + `password`; there is no username path.
RSpec.describe "Sessions", type: :request do
  let(:password) { "supersecret" }
  let!(:user) do
    User.first ||
      create(:user, password: password, password_confirmation: password)
  end

  before do
    user.update!(password: password, password_confirmation: password)
  end

  describe "GET /login", :unauthenticated do
    it "renders the login form with the email-only field" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[log in]")
      expect(response.body).to include('name="email"')
      expect(response.body).to include('name="password"')
      expect(response.body).to include('name="remember_me"')
    end

    it "does not render any legacy username field" do
      get login_path
      expect(response.body).not_to include('name="identifier"')
      expect(response.body).not_to match(/email or username/i)
    end

    it "does not render an inline duplicate of the flash error" do
      post login_path, params: { email: user.email, password: "wrong" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.scan(/invalid email or password/i).length).to eq(1)
      expect(response.body).not_to include("flash-error")
    end

    # Phase 9 — Login-with-Google Drop (ADR 0006). The login form must
    # not expose any third-party-identity affordance. This guards
    # against an accidental reintroduction of a "Sign in with Google"
    # button, divider, or copy.
    it "does not render any Sign in with Google button or third-party divider" do
      get login_path
      body = response.body
      expect(body).not_to match(/sign[- ]?in with google/i)
      expect(body).not_to match(/log[- ]?in with google/i)
      expect(body.downcase).not_to include("google")
      expect(body.downcase).not_to include("oauth")
    end
  end

  describe "POST /login", :unauthenticated do
    it "creates a session, sets a signed cookie, and redirects on success" do
      expect {
        post login_path, params: { email: user.email, password: password }
      }.to change { Session.where(user_id: user.id).count }.by(1)

      expect(response).to have_http_status(:found)
      expect(response.headers["Set-Cookie"].to_s).to include(Sessions::Authenticator::COOKIE_NAME.to_s)

      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be false
    end

    it "is case-insensitive on the email identifier (citext)" do
      expect {
        post login_path, params: { email: user.email.upcase, password: password }
      }.to change { Session.where(user_id: user.id).count }.by(1)
      expect(response).to have_http_status(:found)
    end

    it "strips surrounding whitespace before lookup" do
      expect {
        post login_path, params: { email: "  #{user.email}  ", password: password }
      }.to change { Session.where(user_id: user.id).count }.by(1)
      expect(response).to have_http_status(:found)
    end

    it "renders the generic error and 422 on wrong password" do
      post login_path, params: { email: user.email, password: "not-it" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("invalid email or password")
      # Anchor the regex so the bare-name match doesn't also catch the
      # Rails default session cookie (`_pito_session`).
      cookie_name = Sessions::Authenticator::COOKIE_NAME.to_s
      expect(response.headers["Set-Cookie"].to_s)
        .not_to match(/(?:^|;\s*|,\s*)#{Regexp.escape(cookie_name)}=/)
    end

    it "renders the same generic error on unknown email" do
      post login_path, params: { email: "nobody@nowhere.test", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("invalid email or password")
    end

    it "renders the same generic error on a malformed email" do
      post login_path, params: { email: "garbage-without-an-at", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("invalid email or password")
    end

    it "renders the generic error on a blank email" do
      post login_path, params: { email: "", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("invalid email or password")
    end

    it "ignores stray legacy params (tenant_id, username, admin) on the success path" do
      expect {
        post login_path, params: {
          email: user.email,
          password: password,
          tenant_id: "999",
          username: "hacker",
          admin: "yes"
        }
      }.to change { Session.where(user_id: user.id).count }.by(1)

      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.user_id).to eq(user.id)
    end

    # Phase 9 — Login-with-Google Drop (ADR 0006). The login surface
    # ignores any smuggled third-party-identity parameter; the
    # controller does not read the param at all, so the success path
    # is unaffected. Guards against accidental coupling.
    it "ignores a smuggled google_id_token / google_access_token parameter" do
      expect {
        post login_path, params: {
          email: user.email,
          password: password,
          google_id_token: "fake-id-token",
          google_access_token: "fake-access-token"
        }
      }.to change { Session.where(user_id: user.id).count }.by(1)

      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.user_id).to eq(user.id)
    end

    it "extends the cookie expires when remember_me=yes" do
      post login_path, params: { email: user.email, password: password, remember_me: "yes" }
      expect(response.headers["Set-Cookie"].to_s).to include("expires=")
      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be true
    end

    it "ignores remember_me when not set to the literal yes" do
      post login_path, params: { email: user.email, password: password, remember_me: "true" }
      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be false
    end

    it "throttles after 10 failures from the same IP" do
      11.times do
        post login_path, params: { email: user.email, password: "still-wrong" }
      end
      expect(response).to have_http_status(:too_many_requests)
    end

    it "redirects to the intended URL when one was stashed" do
      get channels_path
      post login_path, params: { email: user.email, password: password }
      expect(response).to redirect_to(channels_path)
    end
  end

  # Phase 8 security audit, finding F1 (account-enumeration timing
  # oracle). The dummy bcrypt compare on the unknown-email branch must
  # use the same bcrypt cost as `has_secure_password` does for real
  # password digests — otherwise an attacker can distinguish "email
  # exists" (real `User#authenticate` at cost 12) from "email doesn't
  # exist" (dummy compare) by wall-clock timing alone.
  #
  # In the test env Rails sets `ActiveModel::SecurePassword.min_cost =
  # true`, so both branches collapse to `MIN_COST` (4) and the asymmetry
  # is invisible. We stub `min_cost` to `false` to simulate production —
  # there the controller MUST pick `BCrypt::Engine.cost` (12), matching
  # what `has_secure_password` uses for real digests. If anyone pins
  # the dummy hash back to a constant `MIN_COST`, this spec fails.
  describe "timing oracle resistance (F1)", :unauthenticated do
    before do
      # Reset the class-level memo so the spec observes the next
      # `BCrypt::Password.create` call.
      SessionsController.instance_variable_set(:@dummy_bcrypt_hash, nil)
    end

    after do
      SessionsController.instance_variable_set(:@dummy_bcrypt_hash, nil)
    end

    it "creates the dummy bcrypt hash at the same cost has_secure_password uses for real digests (production simulation)" do
      # Simulate production: Rails only auto-enables min_cost in the
      # test env. In dev / prod min_cost is false, so the real cost is
      # `BCrypt::Engine.cost` (12 by default).
      allow(ActiveModel::SecurePassword).to receive(:min_cost).and_return(false)

      captured_cost = nil
      allow(BCrypt::Password).to receive(:create).and_wrap_original do |orig, secret, **kwargs|
        captured_cost = kwargs[:cost]
        orig.call(secret, **kwargs)
      end

      post login_path, params: { email: "definitely-nobody@nowhere.test", password: "irrelevant" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(captured_cost).to eq(BCrypt::Engine.cost),
        "dummy bcrypt cost (#{captured_cost.inspect}) must match BCrypt::Engine.cost " \
        "(#{BCrypt::Engine.cost.inspect}) when min_cost is false (i.e. in production). " \
        "Mismatched cost reopens the account-enumeration timing oracle " \
        "(Phase 8 audit finding F1)."
    end
  end

  describe "DELETE /session" do
    it "revokes the session row and clears the cookie" do
      session_row = sign_in_as(user)
      delete session_logout_path

      expect(response).to redirect_to(login_path)
      expect(session_row.reload.revoked?).to be true
      expect(response.headers["Set-Cookie"].to_s).to include("#{Sessions::Authenticator::COOKIE_NAME}=;")
    end
  end

  describe "auth gating" do
    it "redirects unauthenticated callers to /login", :unauthenticated do
      get channels_path
      expect(response).to redirect_to(login_path)
    end

    it "lets authenticated callers through" do
      get root_path
      expect(response).to have_http_status(:ok).or have_http_status(:found)
    end
  end
end
