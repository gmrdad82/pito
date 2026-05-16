require "rails_helper"

# Post-Phase-25 rollback. The new-location approval flow + the
# LoginAttempt forensic surface are gone. The simplified login flow:
#
#   * TOTP-configured user → password verified → redirect to /login/totp.
#   * Non-TOTP user        → password verified → mint session, redirect
#                            to /settings?enroll_totp=1 (mandatory-2FA
#                            gate forces enrollment).
#
# Sad paths (wrong password / unknown username / blank) bottom out
# through the same `login failed.` 422 with no oracle differentiation.
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
    end

    # 2026-05-16 (sessions revamp v2). The "remember me on this device
    # (30 days)" checkbox + the underlying `sessions.remember` column
    # were dropped. The form no longer renders the checkbox; the
    # controller no longer reads `remember_me` from params.
    it "no longer renders the dropped remember-me checkbox" do
      get login_path
      expect(response.body).not_to include('name="remember_me"')
      expect(response.body.downcase).not_to include("remember me on this device")
    end

    it "does not render a legacy email field" do
      get login_path
      expect(response.body).not_to include('name="email"')
      expect(response.body).not_to include('type="email"')
    end

    it "no longer renders the dropped fingerprint hint inputs" do
      get login_path
      expect(response.body).not_to include('name="fp_screen"')
      expect(response.body).not_to include('name="fp_locale"')
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
      # LD-14 — Generic copy is `login failed.` regardless of which
      # step failed.
      expect(response.body.scan(/login failed/i).length).to eq(1)
      expect(response.body).not_to include("flash-error")
    end

    # Phase D polish (2026-05-16) — login form copy + layout.
    describe "login form copy + layout polish" do
      it "does not render the 'sign in with your pito account.' orientation copy" do
        get login_path
        expect(response.body.downcase).not_to include("sign in with your pito account")
      end

      it "does not render the 'forgot your password?' prefix copy" do
        get login_path
        expect(response.body.downcase).not_to include("forgot your password")
      end

      it "places [reset password] in the same dot-list row as [log in], after the form fields" do
        get login_path
        body = response.body

        dot_list_match = body.match(/<div class="dot-list">(.*?)<\/div>/m)
        expect(dot_list_match).not_to be_nil
        dot_list_html = dot_list_match[1]

        expect(dot_list_html).to include("[log in]")
        expect(dot_list_html).to include("reset password")
        expect(dot_list_html.index("[log in]"))
          .to be < dot_list_html.index("reset password")
      end

      it "renders a middle-dot `nav-sep` between [log in] and [reset password]" do
        get login_path
        body = response.body

        dot_list_match = body.match(/<div class="dot-list">(.*?)<\/div>/m)
        expect(dot_list_match).not_to be_nil
        dot_list_html = dot_list_match[1]

        sep_html = '<span class="nav-sep" aria-hidden="true">·</span>'
        expect(dot_list_html).to include(sep_html)

        login_idx = dot_list_html.index("[log in]")
        sep_idx   = dot_list_html.index(sep_html)
        reset_idx = dot_list_html.index("reset password")
        expect(login_idx).to be < sep_idx
        expect(sep_idx).to be < reset_idx
      end

      it "does not place [reset password] above the username field" do
        get login_path
        body = response.body

        username_field_idx = body.index('id="login_username"')
        reset_link_idx     = body.index("reset password")
        expect(username_field_idx).not_to be_nil
        expect(reset_link_idx).not_to be_nil
        expect(reset_link_idx).to be > username_field_idx
      end

      it "renders the heading and submit label as 'log in' (two words, lowercase)" do
        get login_path
        body = response.body

        expect(body).to include("<h1>log in</h1>")
        expect(body).to include("[log in]")
        expect(body).not_to match(/<h1>\s*login\s*<\/h1>/i)
        expect(body).not_to include("[login]")
      end

      it "renders 'reset password' (two words, lowercase) as the bracketed link label" do
        get login_path
        expect(response.body).to include('<span class="bl">reset password</span>')
      end
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

      it "stashes the pre-auth marker cookie before the TOTP redirect" do
        post login_path, params: { username: user.username, password: password }
        cookie_header = response.headers["Set-Cookie"].to_s
        expect(cookie_header).to include(SessionsController::PRE_AUTH_COOKIE.to_s)
      end
    end

    context "user WITHOUT TOTP — first-login bootstrap (R4)" do
      # First-login bootstrap mints an active session directly and
      # redirects to `/settings?enroll_totp=1` so the mandatory-2FA
      # gate's auto-open modal forces enrollment.
      it "mints an active session directly and redirects to /settings?enroll_totp=1" do
        expect {
          post login_path, params: { username: user.username, password: password }
        }.to change { Session.state_active.where(user_id: user.id).count }.by(1)

        expect(response).to redirect_to(settings_path(enroll_totp: 1))
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

    # 2026-05-16 (sessions revamp v2). Session cookies are now
    # session-only — the "remember me" checkbox + the
    # `sessions.remember` column it threaded into were dropped, so
    # the cookie carries no `expires=` attribute. Passing
    # `remember_me` in the form params is silently ignored.
    it "mints a session-only cookie (no expires=) regardless of stray remember_me params" do
      post login_path, params: { username: user.username, password: password, remember_me: "yes" }
      expect(response.headers["Set-Cookie"].to_s).not_to include("expires=")
    end

    it "throttles after 10 failures from the same IP" do
      11.times do
        post login_path, params: { username: user.username, password: "still-wrong" }
      end
      expect(response).to have_http_status(:too_many_requests)
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
