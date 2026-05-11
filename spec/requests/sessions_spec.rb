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
      # Phase 25 — 01a (LD-14). Generic copy is `login failed.` regardless
      # of which step failed. A single occurrence in the body keeps the
      # flash from doubling up.
      expect(response.body.scan(/login failed/i).length).to eq(1)
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
    # Phase 25 — 01b. Many of the original 01a / Phase-8 specs assert
    # "successful POST /login mints a session and redirects to root".
    # Under 01b that's only true for trusted locations. Seed the
    # trusted-location row for the fingerprint the rack-test request
    # produces so those specs keep meaning what they meant.
    def seed_trusted_location_for_test_request!
      # Two-step probe — hit /login with the wrong password once to
      # capture whatever fingerprint the rack-test request env yields,
      # then upsert a TrustedLocation row. The single probe call
      # records one failure on the throttle bucket; the threshold is
      # 10 so the trailing real-login call is well under.
      post login_path, params: { email: user.email, password: "probe-wrong" }
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

    it "creates a session, sets a signed cookie, and redirects on success" do
      seed_trusted_location_for_test_request!

      expect {
        post login_path, params: { email: user.email, password: password }
      }.to change { Session.where(user_id: user.id).count }.by(1)

      expect(response).to have_http_status(:found)
      expect(response.headers["Set-Cookie"].to_s).to include(Sessions::Authenticator::COOKIE_NAME.to_s)

      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be false
    end

    it "is case-insensitive on the email identifier (citext)" do
      seed_trusted_location_for_test_request!

      expect {
        post login_path, params: { email: user.email.upcase, password: password }
      }.to change { Session.where(user_id: user.id).count }.by(1)
      expect(response).to have_http_status(:found)
    end

    it "strips surrounding whitespace before lookup" do
      seed_trusted_location_for_test_request!

      expect {
        post login_path, params: { email: "  #{user.email}  ", password: password }
      }.to change { Session.where(user_id: user.id).count }.by(1)
      expect(response).to have_http_status(:found)
    end

    it "renders the generic error and 422 on wrong password" do
      post login_path, params: { email: user.email, password: "not-it" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("login failed")
      # Anchor the regex so the bare-name match doesn't also catch the
      # Rails default session cookie (`_pito_session`).
      cookie_name = Sessions::Authenticator::COOKIE_NAME.to_s
      expect(response.headers["Set-Cookie"].to_s)
        .not_to match(/(?:^|;\s*|,\s*)#{Regexp.escape(cookie_name)}=/)
    end

    it "renders the same generic error on unknown email" do
      post login_path, params: { email: "nobody@nowhere.test", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("login failed")
    end

    it "renders the same generic error on a malformed email" do
      post login_path, params: { email: "garbage-without-an-at", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("login failed")
    end

    it "renders the generic error on a blank email" do
      post login_path, params: { email: "", password: "irrelevant" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("login failed")
    end

    it "ignores stray legacy params (tenant_id, username, admin) on the success path" do
      seed_trusted_location_for_test_request!

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
      seed_trusted_location_for_test_request!

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
      seed_trusted_location_for_test_request!

      post login_path, params: { email: user.email, password: password, remember_me: "yes" }
      expect(response.headers["Set-Cookie"].to_s).to include("expires=")
      session_row = Session.where(user_id: user.id).order(:created_at).last
      expect(session_row.remember?).to be true
    end

    it "ignores remember_me when not set to the literal yes" do
      seed_trusted_location_for_test_request!

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
      seed_trusted_location_for_test_request!
      post login_path, params: { email: user.email, password: password }
      expect(response).to redirect_to(channels_path)
    end

    # Phase 25 — 01a. Every authenticate POST writes a LoginAttempt row
    # regardless of outcome. The row carries the precise internal
    # reason; the response stays generic per LD-14.
    describe "LoginAttempt writes (Phase 25 — 01a)" do
      it "writes a success row on a clean login" do
        seed_trusted_location_for_test_request!
        # Seeding the row required one probe POST which itself writes a row;
        # reset the LoginAttempt count baseline for the assertion below.
        baseline = LoginAttempt.count

        expect {
          post login_path, params: { email: user.email, password: password }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("success")
        expect(row.reason).to eq("trusted_location_success")
        expect(row.user_id).to eq(user.id)
        expect(LoginAttempt.count).to be > baseline
      end

      it "writes a failed row with reason: wrong_password" do
        expect {
          post login_path, params: { email: user.email, password: "wrong" }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("failed")
        expect(row.reason).to eq("wrong_password")
        expect(row.user_id).to eq(user.id)
      end

      it "writes a failed row with reason: unknown_account on a missing email" do
        expect {
          post login_path, params: { email: "nobody@nowhere.test", password: "x" }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("failed")
        expect(row.reason).to eq("unknown_account")
        expect(row.user_id).to be_nil
        expect(row.email_attempted).to eq("nobody@nowhere.test")
      end

      it "writes a blocked row when the (fingerprint, ip_prefix) is on the auto-block list" do
        # Two-step approach: hit /login once with a wrong password to
        # discover the fingerprint the integration test environment
        # produces (it can differ from `TestRequest.create` because
        # of the default `Accept` / `Accept-Encoding` Rack adds). Seed
        # the BlockedLocation with that fingerprint, then re-hit with
        # the correct password — the block-list check now short-circuits.
        post login_path, params: { email: user.email, password: "wrong-first" }
        first_row = LoginAttempt.recent.first
        expect(first_row.result).to eq("failed")

        create(
          :blocked_location,
          fingerprint_hash: first_row.fingerprint_hash,
          ip_prefix: first_row.ip_prefix,
          blocked_by_user: user
        )

        expect {
          post login_path, params: { email: user.email, password: password }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.result).to eq("blocked")
        expect(row.reason).to eq("blocked_pair")
        # The user does NOT get a session even though the password was right.
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body.downcase).to include("login failed")
      end

      it "composes the fingerprint without screen / locale hint params" do
        # Submitting WITHOUT the hidden `fp_*` fields still writes a row;
        # the composer absorbs the empty values. Under 01b the row is
        # a new-location pending challenge row OR a fresh trust on a
        # trusted-seeded request — either way one row is written.
        seed_trusted_location_for_test_request!

        expect {
          post login_path, params: { email: user.email, password: password }
        }.to change(LoginAttempt, :count).by(1)

        row = LoginAttempt.recent.first
        expect(row.fingerprint_hash.length).to eq(64)
      end
    end

    # Phase 25 — 01b. Trusted / new-location / blocked dispatch.
    describe "new-location dispatch (Phase 25 — 01b)" do
      it "trusted location: mints a session, writes trusted_location_success, redirects to root" do
        # Seed a trusted-location row for the fingerprint/ip_prefix the
        # rack-test request will produce. Two-step: hit /login once
        # (wrong password) to capture the actual fingerprint, then
        # seed the trusted row.
        post login_path, params: { email: user.email, password: "wrong" }
        seed = LoginAttempt.recent.first
        TrustedLocation.create!(
          user: user,
          fingerprint_hash: seed.fingerprint_hash,
          ip_prefix: seed.ip_prefix,
          first_seen_at: 1.day.ago,
          last_seen_at: 1.day.ago
        )

        expect {
          post login_path, params: { email: user.email, password: password }
        }.to change(Session.state_active, :count).by(1)

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(root_path)
        row = LoginAttempt.where(reason: LoginAttempt.reasons[:trusted_location_success]).recent.first
        expect(row).to be_present
      end

      it "new location: does NOT mint a session, redirects to /login/challenge" do
        expect {
          post login_path, params: { email: user.email, password: password }
        }.not_to change(Session.state_active, :count)

        expect(response).to redirect_to(login_challenge_path)
      end

      it "blocked pair: writes a blocked row, renders generic failure" do
        # Seed the block on whatever fingerprint the rack-test request
        # produces (same two-step probe).
        post login_path, params: { email: user.email, password: "wrong" }
        seed = LoginAttempt.recent.first
        create(
          :blocked_location,
          fingerprint_hash: seed.fingerprint_hash,
          ip_prefix: seed.ip_prefix,
          blocked_by_user: user
        )

        expect {
          post login_path, params: { email: user.email, password: password }
        }.to change(LoginAttempt.blocked_results, :count).by(1)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body.downcase).to include("login failed")
      end
    end
  end

  # Phase 8 security audit, finding F1 (account-enumeration timing
  # oracle). The dummy bcrypt compare on the unknown-email branch must
  # use the same bcrypt cost as `has_secure_password` does for real
  # password digests — otherwise an attacker can distinguish "email
  # exists" (real `User#authenticate` at cost 12) from "email doesn't
  # exist" (dummy compare) by wall-clock timing alone.
  #
  # P25 follow-up — F12 reworked this from a lazy class-level memo
  # into a boot-time-computed constant
  # (`config/initializers/sessions_dummy_bcrypt.rb`). The cost-selection
  # logic still mirrors `ActiveModel::SecurePassword.min_cost` so the
  # cost in production is `BCrypt::Engine.cost` (12). This spec asserts
  # against the constant directly — the previous lazy-memo + stub
  # approach is no longer applicable because the hash is computed
  # once at Puma startup before any request runs.
  describe "timing oracle resistance (F1)", :unauthenticated do
    it "Sessions::DUMMY_BCRYPT_COST matches the cost has_secure_password uses for real digests" do
      # Under the test env Rails sets `min_cost = true`, so the
      # constant resolves to `BCrypt::Engine::MIN_COST` (4). In
      # production min_cost is false and the constant resolves to
      # `BCrypt::Engine.cost` (12). The initializer picks the same
      # branch `ActiveModel::SecurePassword` does — verify the live
      # cost matches one of the two valid choices and tracks
      # `min_cost`.
      expected =
        if ActiveModel::SecurePassword.min_cost
          BCrypt::Engine::MIN_COST
        else
          BCrypt::Engine.cost
        end
      expect(Sessions::DUMMY_BCRYPT_COST).to eq(expected)
    end

    it "the hash on the boot-time constant is created at Sessions::DUMMY_BCRYPT_COST" do
      # Read the cost back off the populated hash. Mismatched cost
      # between the constant and the hash itself would reopen the
      # timing oracle.
      live_cost = BCrypt::Password.new(Sessions::DUMMY_BCRYPT_HASH).cost
      expect(live_cost).to eq(Sessions::DUMMY_BCRYPT_COST)
    end

    it "the unknown-email branch does NOT create a new BCrypt hash per request (F12: boot-time only)" do
      # Spy on `BCrypt::Password.create`. After F12 the controller path
      # only calls `BCrypt::Password.new(hash).is_password?` — never
      # `create`. A future regression that reintroduces lazy `create`
      # would re-introduce the first-request timing skew.
      expect(BCrypt::Password).not_to receive(:create)
      post login_path, params: { email: "definitely-nobody@nowhere.test", password: "irrelevant" }
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
