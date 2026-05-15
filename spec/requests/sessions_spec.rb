require "rails_helper"

# Phase 29 — Unit A2. The login form posts `username` + `password`;
# there is no email path. 2FA is mandatory from first login — a
# TOTP-configured user goes through the `/login/totp` challenge; a
# user WITHOUT TOTP gets an active session minted directly (the
# first-login bootstrap, R4) and is then gated into TOTP enrollment.
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
    it "renders the login form with the username field" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[log in]")
      expect(response.body).to include('name="username"')
      expect(response.body).to include('name="password"')
      expect(response.body).to include('name="remember_me"')
    end

    it "does not render a legacy email field" do
      get login_path
      expect(response.body).not_to include('name="email"')
      expect(response.body).not_to include('type="email"')
    end

    it "links [reset password] to /password/reset and drops the credentials:edit copy" do
      get login_path
      expect(response.body).to include(password_reset_path)
      expect(response.body.downcase).to include("reset password")
      expect(response.body).not_to include("credentials:edit")
    end

    it "does not render an inline duplicate of the flash error" do
      post login_path, params: { username: user.username, password: "wrong" }
      expect(response).to have_http_status(:unprocessable_content)
      # Phase 25 — 01a (LD-14). Generic copy is `login failed.` regardless
      # of which step failed.
      expect(response.body.scan(/login failed/i).length).to eq(1)
      expect(response.body).not_to include("flash-error")
    end

    # Phase 9 — Login-with-Google Drop (ADR 0006).
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
    # Phase 25 — 01b. A trusted-location login mints a session and
    # redirects to root. Seed the trusted-location row for the
    # fingerprint the rack-test request produces so those specs keep
    # meaning what they meant.
    def seed_trusted_location_for_test_request!
      post login_path, params: { username: user.username, password: "probe-wrong" }
      seed = LoginAttempt.recent.first
      TrustedLocation.find_or_create_by!(
        user: user,
        fingerprint_hash: seed.fingerprint_hash,
        ip_prefix: seed.ip_prefix
      ) do |row|
        row.first_seen_at = 1.day.ago
        row.last_seen_at  = 1.day.ago
      end
    end

    context "TOTP-configured user" do
      before { user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago) }

      it "routes a valid username + password to the /login/totp challenge" do
        expect {
          post login_path, params: { username: user.username, password: password }
        }.not_to change(Session, :count)

        expect(response).to redirect_to(login_totp_path)
      end

      it "is case-insensitive on the username identifier (citext)" do
        post login_path, params: { username: user.username.upcase, password: password }
        expect(response).to redirect_to(login_totp_path)
      end

      it "strips surrounding whitespace before lookup" do
        post login_path, params: { username: "  #{user.username}  ", password: password }
        expect(response).to redirect_to(login_totp_path)
      end
    end

    context "user WITHOUT TOTP — first-login bootstrap (R4)" do
      it "mints an active session directly and redirects to the TOTP setup page" do
        expect {
          post login_path, params: { username: user.username, password: password }
        }.to change { Session.state_active.where(user_id: user.id).count }.by(1)

        expect(response).to redirect_to(settings_security_totp_path)
      end

      it "records LoginAttempt.reason = first_login_totp_setup_required" do
        post login_path, params: { username: user.username, password: password }

        row = LoginAttempt.recent.first
        expect(row.reason).to eq("first_login_totp_setup_required")
        expect(row.result).to eq("success")
        expect(row.user_id).to eq(user.id)
      end

      it "sets the session cookie so the post-session gate takes over" do
        post login_path, params: { username: user.username, password: password }
        expect(response.headers["Set-Cookie"].to_s)
          .to include(Sessions::Authenticator::COOKIE_NAME.to_s)
      end
    end

    it "renders the generic error and 422 on wrong password" do
      post login_path, params: { username: user.username, password: "not-it" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("login failed")
      cookie_name = Sessions::Authenticator::COOKIE_NAME.to_s
      expect(response.headers["Set-Cookie"].to_s)
        .not_to match(/(?:^|;\s*|,\s*)#{Regexp.escape(cookie_name)}=/)
    end

    it "renders the same generic error on an unknown username (no oracle)" do
      post login_path, params: { username: "nobody_here", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("login failed")
    end

    it "produces an indistinguishable response for unknown-username and wrong-password" do
      # No oracle: a real user with the wrong password and a
      # nonexistent username produce the same status, the same
      # generic flash copy, and no session cookie. The form echoes
      # back the typed username (the user's own input), so normalize
      # the echo out before comparing bodies.
      cookie_name = Sessions::Authenticator::COOKIE_NAME.to_s

      post login_path, params: { username: user.username, password: "wrong-pw" }
      wrong_status = response.status
      wrong_body   = response.body.gsub(user.username, "X")
      wrong_cookie = response.headers["Set-Cookie"].to_s

      post login_path, params: { username: "nonexistent_user", password: "wrong-pw" }
      unknown_status = response.status
      unknown_body   = response.body.gsub("nonexistent_user", "X")
      unknown_cookie = response.headers["Set-Cookie"].to_s

      expect(unknown_status).to eq(wrong_status)
      expect(unknown_status).to eq(422)
      expect(unknown_body).to eq(wrong_body)
      # Anchor the match so the app's own `pito_session` auth cookie
      # is checked — not Rails' default `_pito_session` session cookie.
      anchored = /(?:^|;\s*|,\s*)#{Regexp.escape(cookie_name)}=/
      expect(wrong_cookie).not_to match(anchored)
      expect(unknown_cookie).not_to match(anchored)
    end

    it "renders the generic error on a blank username" do
      post login_path, params: { username: "", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("login failed")
    end

    it "ignores stray legacy params (tenant_id, email, admin) on the success path" do
      expect {
        post login_path, params: {
          username: user.username,
          password: password,
          tenant_id: "999",
          email: "hacker@example.test",
          admin: "yes"
        }
      }.to change { Session.where(user_id: user.id).count }.by(1)

      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.user_id).to eq(user.id)
    end

    it "ignores a smuggled google_id_token / google_access_token parameter" do
      expect {
        post login_path, params: {
          username: user.username,
          password: password,
          google_id_token: "fake-id-token",
          google_access_token: "fake-access-token"
        }
      }.to change { Session.where(user_id: user.id).count }.by(1)
    end

    it "extends the cookie expires when remember_me=yes" do
      post login_path, params: { username: user.username, password: password, remember_me: "yes" }
      expect(response.headers["Set-Cookie"].to_s).to include("expires=")
      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be true
    end

    it "ignores remember_me when not set to the literal yes" do
      post login_path, params: { username: user.username, password: password, remember_me: "true" }
      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be false
    end

    it "throttles after 10 failures from the same IP" do
      11.times do
        post login_path, params: { username: user.username, password: "still-wrong" }
      end
      expect(response).to have_http_status(:too_many_requests)
    end

    it "redirects to the intended URL when one was stashed (trusted location)" do
      get channels_path
      seed_trusted_location_for_test_request!
      user.update!(totp_seed_encrypted: nil, totp_enabled_at: nil)
      post login_path, params: { username: user.username, password: password }
      expect(response).to redirect_to(channels_path)
    end

    # Phase 25 — 01a. Every authenticate POST writes a LoginAttempt row.
    describe "LoginAttempt writes (Phase 25 — 01a)" do
      it "writes a success row on a clean trusted-location login" do
        seed_trusted_location_for_test_request!
        baseline = LoginAttempt.count

        expect {
          post login_path, params: { username: user.username, password: password }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("success")
        expect(row.reason).to eq("trusted_location_success")
        expect(row.user_id).to eq(user.id)
        expect(LoginAttempt.count).to be > baseline
      end

      it "writes a failed row with reason: wrong_password" do
        expect {
          post login_path, params: { username: user.username, password: "wrong" }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("failed")
        expect(row.reason).to eq("wrong_password")
        expect(row.user_id).to eq(user.id)
      end

      it "writes a failed row with reason: unknown_account on a missing username" do
        expect {
          post login_path, params: { username: "nobody_known", password: "x" }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("failed")
        expect(row.reason).to eq("unknown_account")
        expect(row.user_id).to be_nil
        expect(row.email_attempted).to eq("nobody_known")
      end

      it "writes a blocked row when the (fingerprint, ip_prefix) is on the auto-block list" do
        post login_path, params: { username: user.username, password: "wrong-first" }
        first_row = LoginAttempt.recent.first
        expect(first_row.result).to eq("failed")

        create(
          :blocked_location,
          fingerprint_hash: first_row.fingerprint_hash,
          ip_prefix: first_row.ip_prefix,
          blocked_by_user: user
        )

        expect {
          post login_path, params: { username: user.username, password: password }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("blocked")
        expect(row.reason).to eq("blocked_pair")
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body.downcase).to include("login failed")
      end

      it "composes the fingerprint without screen / locale hint params" do
        expect {
          post login_path, params: { username: user.username, password: password }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.fingerprint_hash.length).to eq(64)
      end
    end

    # Phase 25 — 01b. Trusted / blocked dispatch (the new-location path
    # for a no-TOTP user is the first-login bootstrap, covered above).
    describe "new-location dispatch (Phase 25 — 01b)" do
      it "trusted location: mints a session, writes trusted_location_success, redirects to root" do
        post login_path, params: { username: user.username, password: "wrong" }
        seed = LoginAttempt.recent.first
        TrustedLocation.create!(
          user: user,
          fingerprint_hash: seed.fingerprint_hash,
          ip_prefix: seed.ip_prefix,
          first_seen_at: 1.day.ago,
          last_seen_at: 1.day.ago
        )

        expect {
          post login_path, params: { username: user.username, password: password }
        }.to change(Session.state_active, :count).by(1)

        expect(response).to redirect_to(root_path)
        row = LoginAttempt.where(reason: LoginAttempt.reasons[:trusted_location_success]).recent.first
        expect(row).to be_present
      end

      it "blocked pair: writes a blocked row, renders generic failure" do
        post login_path, params: { username: user.username, password: "wrong" }
        seed = LoginAttempt.recent.first
        create(
          :blocked_location,
          fingerprint_hash: seed.fingerprint_hash,
          ip_prefix: seed.ip_prefix,
          blocked_by_user: user
        )

        expect {
          post login_path, params: { username: user.username, password: password }
        }.to change(LoginAttempt.blocked_results, :count).by(1)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body.downcase).to include("login failed")
      end
    end
  end

  # Phase 8 security audit, finding F1 (account-enumeration timing
  # oracle). The dummy bcrypt compare on the unknown-username branch
  # must use the same bcrypt cost as `has_secure_password`.
  describe "timing oracle resistance (F1)", :unauthenticated do
    it "Sessions::DUMMY_BCRYPT_COST matches the cost has_secure_password uses for real digests" do
      expected =
        if ActiveModel::SecurePassword.min_cost
          BCrypt::Engine::MIN_COST
        else
          BCrypt::Engine.cost
        end
      expect(Sessions::DUMMY_BCRYPT_COST).to eq(expected)
    end

    it "the hash on the boot-time constant is created at Sessions::DUMMY_BCRYPT_COST" do
      live_cost = BCrypt::Password.new(Sessions::DUMMY_BCRYPT_HASH).cost
      expect(live_cost).to eq(Sessions::DUMMY_BCRYPT_COST)
    end

    it "the unknown-username branch does NOT create a new BCrypt hash per request (F12: boot-time only)" do
      expect(BCrypt::Password).not_to receive(:create)
      post login_path, params: { username: "definitely_nobody", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
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
