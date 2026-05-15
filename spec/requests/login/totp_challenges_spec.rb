require "rails_helper"

# Phase 25 — 01e. Request specs for /login/totp.
RSpec.describe "Login::TotpChallenges", type: :request do
  let(:password) { "supersecret-totp" }
  let(:seed) { "JBSWY3DPEHPK3PXP" }
  # P25 follow-up — F4. Must use the safe 28-char alphabet
  # (no O / I / L / B / 8 / 0 / 1) and be exactly 8 chars; otherwise
  # the consumer short-circuits at the alphabet gate.
  let(:backup_plaintext) { "ACDE2345" }
  let!(:user) do
    User.first ||
      create(:user, password: password, password_confirmation: password)
  end

  # P25 follow-up — F8. The pre-auth nonce mechanism rides on
  # Rails.cache. Test env's default :null_store would silently drop
  # the nonce write — making every TOTP submit fail the cache-side
  # nonce check. Swap to a real MemoryStore for the whole file so the
  # legitimate flow + the rotation flow are both observable.
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(memory_cache)

    user.update!(
      password: password,
      password_confirmation: password,
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago
    )
    user.totp_backup_codes.destroy_all
    user.totp_backup_codes.create!(code_digest: BCrypt::Password.create(backup_plaintext))
    # P25 follow-up — F9. Reset the replay-defense watermark so each
    # test computes a fresh-window verify and is not blocked by a
    # prior test's stamp within the same 30-s window.
    user.update_columns(totp_last_used_step: nil)
  end

  def post_login_with_password
    post login_path, params: { username: user.username, password: password }
  end

  describe "GET /login/totp", :unauthenticated do
    it "returns 200 when the pre-auth marker is present (post-password)" do
      post_login_with_password
      expect(response).to redirect_to(login_totp_path)
      get login_totp_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("authenticator")
      # Bracketed-link inner-padding fix: verify button uses the
      # canonical <span class="bl"> wrap.
      expect(response.body).to include('[<span class="bl">verify</span>]')
    end

    it "redirects to /login without a pre-auth marker" do
      get login_totp_path
      expect(response).to redirect_to(login_path)
    end

    it "redirects to /login/challenge when 2FA is not enabled (and short-circuits the show render)" do
      # Drive the controller through the pre-auth marker path while 2FA
      # is off — the show action must redirect and `return` so the view
      # does not also try to render. A missing `return` would not raise
      # in Rails (the redirect wins), but the `before_action` flow + a
      # double response would attempt to set status twice. We assert
      # the redirect status and lack of body to lock the path.
      post_login_with_password
      user.update!(totp_enabled_at: nil, totp_disabled_at: Time.current)
      get login_totp_path
      expect(response).to redirect_to(login_challenge_path)
      expect(response.body).not_to include("enter a 6-digit code from your authenticator")
    end
  end

  describe "POST /login/totp", :unauthenticated do
    before { post_login_with_password }

    it "with the correct TOTP code activates the session and rotates the token" do
      code = ROTP::TOTP.new(seed).now
      expect {
        post login_totp_path, params: { code: code }
      }.to change(Session.state_active, :count).by(1)

      expect(response).to redirect_to(root_path)
    end

    it "with the correct TOTP code writes a LoginAttempt with reason: new_location_2fa_passed" do
      code = ROTP::TOTP.new(seed).now
      expect {
        post login_totp_path, params: { code: code }
      }.to change(LoginAttempt.where(reason: LoginAttempt.reasons[:new_location_2fa_passed]), :count).by(1)
    end

    it "with a valid backup code stamps used_at and activates" do
      expect {
        post login_totp_path, params: { code: backup_plaintext }
      }.to change(Session.state_active, :count).by(1)

      row = user.totp_backup_codes.first
      expect(row.reload.used_at).to be_present
    end

    it "with a wrong code returns 422 and writes a twofa_failed LoginAttempt" do
      expect {
        post login_totp_path, params: { code: "000000" }
      }.to change(LoginAttempt.where(reason: LoginAttempt.reasons[:twofa_failed]), :count).by(1)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "with an already-used backup code returns 422" do
      row = user.totp_backup_codes.first
      row.update!(used_at: 1.minute.ago)

      expect {
        post login_totp_path, params: { code: backup_plaintext }
      }.to change(LoginAttempt.where(reason: LoginAttempt.reasons[:twofa_failed]), :count).by(1)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /login/totp without a pre-auth marker", :unauthenticated do
    it "redirects (HTML) to /login" do
      post login_totp_path, params: { code: "123456" }
      expect(response).to redirect_to(login_path)
    end
  end

  # P25 follow-up — F8. Pre-auth nonce rotation. The cookie carries a
  # nonce mirrored in Rails.cache; cookie-nonce must equal cache-nonce
  # on every TOTP submit. On failed submit, the controller rotates
  # BOTH (cache write + cookie re-mint) so a stolen cookie's brute
  # force is bounded to ~1 attempt before the nonce rotates.
  describe "POST /login/totp pre-auth nonce rotation (P25 F8)", :unauthenticated do
    # The file-level `before` already swaps Rails.cache to a real
    # MemoryStore. These specs assert against that store directly.
    before do
      post_login_with_password
    end

    it "writes a nonce to cache when the pre-auth marker is minted" do
      cache_key = SessionsController.pre_auth_nonce_cache_key(user.id)
      expect(memory_cache.read(cache_key)).to be_present
    end

    it "fresh cookie + cache nonce → success (legit flow)" do
      code = ROTP::TOTP.new(seed).now
      expect {
        post login_totp_path, params: { code: code }
      }.to change(Session.state_active, :count).by(1)
    end

    it "deletes the cache nonce on success" do
      code = ROTP::TOTP.new(seed).now
      post login_totp_path, params: { code: code }
      cache_key = SessionsController.pre_auth_nonce_cache_key(user.id)
      expect(memory_cache.read(cache_key)).to be_nil
    end

    it "wrong code → rotates the cache nonce on failure" do
      cache_key = SessionsController.pre_auth_nonce_cache_key(user.id)
      old_nonce = memory_cache.read(cache_key)
      post login_totp_path, params: { code: "000000" }
      new_nonce = memory_cache.read(cache_key)
      expect(new_nonce).to be_present
      expect(new_nonce).not_to eq(old_nonce)
    end

    it "wrong code → response is 422 (generic), no nonce-mismatch leak in body" do
      post login_totp_path, params: { code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body.downcase).to include("login failed.")
      expect(response.body.downcase).not_to include("nonce")
    end

    it "mismatched cookie nonce → 422 (simulates a stale stolen cookie)" do
      # The cookie still carries the original nonce; rotate the cache
      # to a different value to simulate the legitimate-user retry
      # path. The next POST should fail closed.
      cache_key = SessionsController.pre_auth_nonce_cache_key(user.id)
      memory_cache.write(cache_key, "some-other-nonce", expires_in: 10.minutes)

      code = ROTP::TOTP.new(seed).now
      post login_totp_path, params: { code: code }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "cache miss (evicted entry) → 422 (fails closed)" do
      cache_key = SessionsController.pre_auth_nonce_cache_key(user.id)
      memory_cache.delete(cache_key)

      code = ROTP::TOTP.new(seed).now
      post login_totp_path, params: { code: code }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "bounds a stolen-cookie brute force to ~1 attempt per nonce rotation" do
      # Capture the cookie value the legitimate flow minted (mirrors a
      # cookie theft). Each subsequent reuse of this captured cookie
      # should land on the rotated-nonce branch and 422.
      stolen_cookie = cookies[SessionsController::PRE_AUTH_COOKIE.to_s]
      expect(stolen_cookie).to be_present

      # First attempt with the cookie + wrong code: 422 + rotation.
      post login_totp_path, params: { code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)

      # Reset the integration session's cookies to JUST the stolen
      # value (the attacker doesn't carry the rotated cookie the
      # response set). Subsequent attempts should now mismatch the
      # rotated cache nonce → 422 without ever reaching the verifier.
      cookies[SessionsController::PRE_AUTH_COOKIE.to_s] = stolen_cookie

      code = ROTP::TOTP.new(seed).now
      post login_totp_path, params: { code: code }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
