require "rails_helper"

# Phase 29 — Unit A2. Reset-password-via-2FA (`/password/reset`).
#
# pito has no email, so this is the only self-service browser
# recovery path: a user proves possession of their TOTP authenticator
# (a live 6-digit code) OR a backup code (single-use, consumed) and is
# then allowed to set a new password. Treated with the same care as
# login — throttled, no account-existence oracle, generic failure
# copy, every session revoked on success, no auto-login.
RSpec.describe "Password resets", :unauthenticated, type: :request do
  let(:password) { "old-password-123" }
  let(:seed)     { "JBSWY3DPEHPK3PXP" }
  let!(:user) do
    create(
      :user,
      password: password,
      password_confirmation: password,
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago
    )
  end

  # The reset marker is a signed cookie + a `Rails.cache` nonce. The
  # test env's :null_store would drop the nonce write and break the
  # marker round-trip, so swap in a real MemoryStore (same pattern as
  # the TOTP journey specs, which depend on a cache-backed one-shot
  # payload).
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    Rack::Attack.cache.store.clear
    allow(Rails).to receive(:cache).and_return(memory_cache)
  end

  def live_code
    ROTP::TOTP.new(seed).now
  end

  describe "GET /password/reset" do
    it "renders the username + code form (200, anonymous-allowed)" do
      get password_reset_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="username"')
      expect(response.body).to include('name="code"')
    end
  end

  describe "POST /password/reset — happy paths" do
    it "verifies a live TOTP code, sets the reset marker, redirects to the edit step" do
      post password_reset_path, params: { username: user.username, code: live_code }
      expect(response).to redirect_to(edit_password_reset_path)

      get edit_password_reset_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="password"')
    end

    it "completes a full reset: PATCH changes the password and revokes every session" do
      active   = Session.create_for!(user: user, ip: "1.1.1.1", user_agent: "x").first
      pending  = create(:session, :pending, user: user)

      post password_reset_path, params: { username: user.username, code: live_code }
      patch password_reset_path, params: {
        password: "brand-new-password-9",
        password_confirmation: "brand-new-password-9"
      }

      expect(response).to redirect_to(login_path)
      expect(flash[:notice]).to be_present
      expect(user.reload.authenticate("brand-new-password-9")).to be_truthy
      expect(user.authenticate(password)).to be(false)
      expect(active.reload.revoked?).to be(true)
      expect(pending.reload.revoked?).to be(true)
    end

    it "accepts a valid backup code and consumes it (single-use, per R1)" do
      # 8 chars from the safe alphabet (`A-Z` + `2-9` minus O/I/L/B/8).
      plaintext = "ZXCVK234"
      user.totp_backup_codes.create!(code_digest: BCrypt::Password.create(plaintext))

      post password_reset_path, params: { username: user.username, code: plaintext }
      expect(response).to redirect_to(edit_password_reset_path)

      code_row = user.totp_backup_codes.order(:created_at).last
      expect(code_row.reload.used_at).to be_present

      # A second reset attempt with the SAME backup code fails — it
      # has been consumed.
      Rack::Attack.cache.store.clear
      post password_reset_path, params: { username: user.username, code: plaintext }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("reset failed")
    end

    it "does NOT establish a session on a successful reset" do
      post password_reset_path, params: { username: user.username, code: live_code }
      patch password_reset_path, params: {
        password: "another-new-pass-1",
        password_confirmation: "another-new-pass-1"
      }

      cookie_name = Sessions::Authenticator::COOKIE_NAME.to_s
      set_cookie = response.headers["Set-Cookie"].to_s
      # No live `pito_session` auth cookie value is written. Anchor the
      # match so Rails' default `_pito_session` session cookie does not
      # trip the assertion.
      expect(set_cookie).not_to match(/(?:^|;\s*|,\s*|\[")#{Regexp.escape(cookie_name)}=[^;]+;/)
    end
  end

  describe "POST /password/reset — sad paths (no oracle)" do
    it "returns the generic failure for a nonexistent username, no marker set" do
      post password_reset_path, params: { username: "nobody_known", code: "123456" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("reset failed")
      expect(cookies[PasswordResetsController::RESET_COOKIE]).to be_blank
    end

    it "returns the generic failure for a known username WITHOUT TOTP configured" do
      no_totp = create(:user, password: password, password_confirmation: password)

      post password_reset_path, params: { username: no_totp.username, code: "123456" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("reset failed")
      expect(cookies[PasswordResetsController::RESET_COOKIE]).to be_blank
    end

    it "returns the generic failure for a valid username + wrong code, no marker" do
      post password_reset_path, params: { username: user.username, code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("reset failed")
      expect(cookies[PasswordResetsController::RESET_COOKIE]).to be_blank
    end

    it "produces the identical response shape for unknown / no-2fa / wrong-code" do
      post password_reset_path, params: { username: "ghost_user", code: "111111" }
      unknown_status, unknown_body = response.status, response.body

      no_totp = create(:user, password: password, password_confirmation: password)
      post password_reset_path, params: { username: no_totp.username, code: "111111" }
      no_totp_status, no_totp_body = response.status, response.body

      post password_reset_path, params: { username: user.username, code: "111111" }
      wrong_status, wrong_body = response.status, response.body

      expect(unknown_status).to eq(422)
      expect(no_totp_status).to eq(422)
      expect(wrong_status).to eq(422)
      # The form echoes the typed username — normalize it out, then the
      # three responses are byte-identical (no oracle).
      norm = ->(body, name) { body.gsub(name, "X") }
      expect(norm.call(no_totp_body, no_totp.username)).to eq(norm.call(wrong_body, user.username))
      expect(norm.call(unknown_body, "ghost_user")).to eq(norm.call(wrong_body, user.username))
    end
  end

  describe "GET /password/reset/edit — marker gating" do
    it "redirects back to /password/reset without a valid reset marker" do
      get edit_password_reset_path
      expect(response).to redirect_to(password_reset_path)
    end
  end

  describe "PATCH /password/reset — marker gating + validation" do
    it "redirects back to /password/reset without a valid marker" do
      patch password_reset_path, params: {
        password: "whatever-12345",
        password_confirmation: "whatever-12345"
      }
      expect(response).to redirect_to(password_reset_path)
    end

    it "re-renders 422 on mismatched passwords and does NOT consume the marker" do
      post password_reset_path, params: { username: user.username, code: live_code }

      patch password_reset_path, params: {
        password: "mismatch-a-111",
        password_confirmation: "mismatch-b-222"
      }
      expect(response).to have_http_status(:unprocessable_content)

      # The marker survived — a corrected retry still works.
      patch password_reset_path, params: {
        password: "corrected-pass-3",
        password_confirmation: "corrected-pass-3"
      }
      expect(response).to redirect_to(login_path)
      expect(user.reload.authenticate("corrected-pass-3")).to be_truthy
    end

    it "re-renders 422 on a too-short password" do
      post password_reset_path, params: { username: user.username, code: live_code }
      patch password_reset_path, params: {
        password: "short",
        password_confirmation: "short"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # Phase 29 — Unit A2 follow-up — security finding F1.
  # A successful password reset must revoke EVERY bearer credential
  # the user holds — not only their cookie sessions. Without this,
  # a leaked password + exfiltrated ApiToken / Doorkeeper grant
  # survives the reset and continues to grant full-scope access.
  describe "bearer-credential revocation on a successful reset (F1)" do
    let(:oauth_application) { create(:oauth_application, scopes: Scopes::APP) }

    def complete_reset!(new_password: "brand-new-password-9")
      post password_reset_path, params: { username: user.username, code: live_code }
      patch password_reset_path, params: {
        password: new_password,
        password_confirmation: new_password
      }
    end

    it "revokes every ApiToken owned by the user" do
      api_token_record, _plaintext = ApiToken.generate!(
        user: user,
        name: "leaked-token-#{SecureRandom.hex(4)}",
        scopes: [ Scopes::APP ]
      )
      other_user = create(:user, totp_seed_encrypted: seed, totp_enabled_at: 1.hour.ago)
      other_token, _ = ApiToken.generate!(
        user: other_user,
        name: "other-#{SecureRandom.hex(4)}",
        scopes: [ Scopes::APP ]
      )

      complete_reset!

      expect(api_token_record.reload.revoked?).to be(true)
      expect(api_token_record.reload.revoked_at).to be_within(5.seconds).of(Time.current)
      # Cross-user isolation: only `user`'s tokens are touched.
      expect(other_token.reload.revoked?).to be(false)
    end

    it "preserves already-revoked ApiToken rows' `revoked_at` (idempotent — does not re-stamp)" do
      already_revoked, _ = ApiToken.generate!(
        user: user,
        name: "already-revoked",
        scopes: [ Scopes::APP ]
      )
      old_stamp = 1.day.ago.change(usec: 0)
      already_revoked.update_columns(revoked_at: old_stamp)

      complete_reset!

      # `update_all` filters on `revoked_at: nil`, so already-revoked
      # rows are NOT re-stamped — the original revocation timestamp is
      # preserved (important for forensic accuracy).
      expect(already_revoked.reload.revoked_at.to_i).to eq(old_stamp.to_i)
    end

    it "revokes every Doorkeeper::AccessToken owned by the user" do
      access_token = Doorkeeper::AccessToken.create!(
        application: oauth_application,
        resource_owner_id: user.id,
        scopes: Scopes::APP,
        expires_in: 7200
      )
      other_user = create(:user, totp_seed_encrypted: seed, totp_enabled_at: 1.hour.ago)
      other_oauth = Doorkeeper::AccessToken.create!(
        application: oauth_application,
        resource_owner_id: other_user.id,
        scopes: Scopes::APP,
        expires_in: 7200
      )

      complete_reset!

      expect(access_token.reload.revoked?).to be(true)
      expect(access_token.reload.revoked_at).to be_within(5.seconds).of(Time.current)
      expect(other_oauth.reload.revoked?).to be(false)
    end

    it "revokes every Doorkeeper::AccessGrant owned by the user" do
      grant = Doorkeeper::AccessGrant.create!(
        application: oauth_application,
        resource_owner_id: user.id,
        token: SecureRandom.hex(32),
        redirect_uri: "http://127.0.0.1:8765/callback",
        scopes: Scopes::APP,
        expires_in: 600
      )

      complete_reset!

      expect(grant.reload.revoked?).to be(true)
      expect(grant.reload.revoked_at).to be_within(5.seconds).of(Time.current)
    end

    it "writes an AuthAuditLog row with revocation tallies in metadata" do
      _api_token, _ = ApiToken.generate!(
        user: user,
        name: "audited-token",
        scopes: [ Scopes::APP ]
      )
      Doorkeeper::AccessToken.create!(
        application: oauth_application,
        resource_owner_id: user.id,
        scopes: Scopes::APP,
        expires_in: 7200
      )
      Doorkeeper::AccessGrant.create!(
        application: oauth_application,
        resource_owner_id: user.id,
        token: SecureRandom.hex(32),
        redirect_uri: "http://127.0.0.1:8765/callback",
        scopes: Scopes::APP,
        expires_in: 600
      )
      Session.create_for!(user: user, ip: "1.1.1.1", user_agent: "x")

      expect { complete_reset! }.to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.order(:created_at).last
      expect(row.action).to eq("password_reset")
      expect(row.acting_user_id).to eq(user.id)
      expect(row.target_id).to eq(user.id)
      meta = row.metadata
      expect(meta["sessions_revoked"]).to be >= 1
      expect(meta["api_tokens_revoked"]).to eq(1)
      expect(meta["oauth_access_tokens_revoked"]).to eq(1)
      expect(meta["oauth_access_grants_revoked"]).to eq(1)
    end

    it "does NOT revoke bearer credentials when the password write fails" do
      api_token_record, _ = ApiToken.generate!(
        user: user,
        name: "survives-failure",
        scopes: [ Scopes::APP ]
      )

      post password_reset_path, params: { username: user.username, code: live_code }
      patch password_reset_path, params: {
        password: "short", # fails the min-length validation
        password_confirmation: "short"
      }
      expect(response).to have_http_status(:unprocessable_content)

      # The token survives the failed reset — only a SUCCESSFUL reset
      # invalidates bearer credentials.
      expect(api_token_record.reload.revoked?).to be(false)
    end
  end

  # Phase 29 — Unit A2 follow-up — security finding F2.
  # The wrong-code branch of `POST /password/reset` used to pay only
  # the (cheap, sub-millisecond) TOTP verifier round-trip plus a
  # bcrypt-per-backup-code loop that short-circuits on a wrong-shape
  # code — making it observably faster than the unknown-username /
  # no-TOTP branches that always pay `bcrypt_dummy_compare`. The fix
  # adds an explicit `bcrypt_dummy_compare` call on the wrong-code
  # branch BEFORE rendering the generic failure.
  describe "wrong-code branch timing symmetrization (F2)" do
    it "invokes `bcrypt_dummy_compare` on the wrong-code path before rendering" do
      # Stub via `any_instance_of` so the method ownership on the
      # class stays untouched — that's important for the F6 concern
      # specs which assert `instance_method(:bcrypt_dummy_compare).owner`.
      expect_any_instance_of(PasswordResetsController)
        .to receive(:bcrypt_dummy_compare).at_least(:once).and_call_original

      post password_reset_path, params: { username: user.username, code: "000000" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("reset failed")
    end

    it "invokes `bcrypt_dummy_compare` on the wrong-shape-code path too (the formerly fast path)" do
      # A "wrong-shape" code (mixed case / wrong length) short-circuits
      # the backup-code consumer before any per-row BCrypt compare.
      # That was the fastest leak vector — and is exactly the branch
      # the F2 fix must symmetrize.
      expect_any_instance_of(PasswordResetsController)
        .to receive(:bcrypt_dummy_compare).at_least(:once).and_call_original

      post password_reset_path, params: { username: user.username, code: "lower-case-and-wrong-shape" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "throttling" do
    it "429s the 6th POST /password/reset from one IP inside a minute" do
      6.times do
        post password_reset_path, params: { username: "spam_user", code: "000000" }
      end
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body.downcase).to include("reset failed")
    end

    it "429s the 11th POST for one username across rotating IPs (per-username bucket)" do
      10.times do |i|
        post password_reset_path,
             params: { username: "throttled_target", code: "000000" },
             headers: { "REMOTE_ADDR" => "10.5.#{i}.1" }
        expect(response).not_to have_http_status(:too_many_requests)
      end

      post password_reset_path,
           params: { username: "throttled_target", code: "000000" },
           headers: { "REMOTE_ADDR" => "10.5.99.1" }
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
