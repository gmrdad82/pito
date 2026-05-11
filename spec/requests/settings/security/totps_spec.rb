require "rails_helper"

# Phase 25 — 01e. Request specs for /settings/security/totp*.
RSpec.describe "Settings::Security::Totps", type: :request do
  let(:user) { User.first || create(:user) }

  describe "GET /settings/security/totp" do
    it "renders 200 with the [ enable 2FA ] CTA when 2FA is off" do
      get settings_security_totp_path
      expect(response).to have_http_status(:ok)
      # Bracketed-link inner-padding fix: label wrapped in <span class="bl">.
      expect(response.body).to include('[<span class="bl">enable 2FA</span>]')
      expect(response.body).to include("off")
    end

    it "renders the disable + backup-codes management links when 2FA is on" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
      get settings_security_totp_path
      expect(response.body).to include("on")
      expect(response.body).to include("[disable]").or include("disable")
      expect(response.body).to include("backup codes")
    end
  end

  describe "POST /settings/security/totp (enroll)" do
    # P25 follow-up — F2. The one-shot enrollment payload now lives in
    # Rails.cache (NOT flash). Test env's :null_store would drop writes
    # silently — swap to MemoryStore for the enroll/show flow.
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(memory_cache) }

    it "creates the seed and 10 backup codes" do
      expect {
        post settings_security_totp_path
      }.to change { user.reload.totp_backup_codes.count }.by(10)

      expect(user.reload.totp_seed_encrypted).to be_present
      expect(response).to redirect_to(settings_security_totp_show_path)
    end

    # P25 F2 — assert the cache entry, NOT the flash entry.
    it "writes the one-shot {seed, codes} to Rails.cache (P25 F2)" do
      post settings_security_totp_path
      cache_key = Settings::Security::TotpsController.enrollment_cache_key(user.id)
      payload = memory_cache.read(cache_key)
      expect(payload).to be_a(Hash)
      expect(payload[:seed]).to be_present
      expect(Array(payload[:codes]).length).to eq(10)

      # Flash MUST NOT carry the plaintext payload.
      expect(flash[:totp_enrollment_one_shot]).to be_nil
    end

    it "redirects with an error when 2FA is already enabled" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
      post settings_security_totp_path
      expect(response).to redirect_to(settings_security_totp_path)
      expect(flash[:alert]).to include("already on")
    end
  end

  describe "GET /settings/security/totp/show (one-shot view)" do
    # P25 F2 — one-shot payload lives in Rails.cache. Swap stores.
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(memory_cache) }

    it "renders 200 when the one-shot payload is in the cache" do
      post settings_security_totp_path
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("scan")
      expect(response.body).to include("confirm")
      # Bracketed-link inner-padding fix: confirm-2FA button uses
      # the canonical <span class="bl"> wrap.
      expect(response.body).to include('[<span class="bl">confirm 2FA</span>]')
    end

    it "redirects to the status page when no one-shot payload is present" do
      get settings_security_totp_show_path
      expect(response).to redirect_to(settings_security_totp_path)
      expect(flash[:alert]).to include("enrollment expired")
    end

    # P25 F2 — re-GET within the 5-min TTL still renders (we
    # intentionally do NOT delete on read; confirm-success deletes).
    # This mirrors the previous `flash.keep` behavior without leaving
    # plaintext in the session cookie.
    it "renders successive GETs within the TTL (no delete-on-read)" do
      post settings_security_totp_path
      get settings_security_totp_show_path
      expect(response).to have_http_status(:ok)
      get settings_security_totp_show_path
      expect(response).to have_http_status(:ok)
    end

    # 2026-05-11 — QR codes need black-on-white contrast to scan
    # reliably. The dark theme renders the page on a dark
    # background which makes the SVG (black modules on
    # transparent) unreadable. The view wraps the QR SVG in a
    # white-bg inline-block so the QR is always readable
    # regardless of theme.
    it "wraps the QR SVG in a white-background inline-block" do
      post settings_security_totp_path
      follow_redirect!
      # The wrapper carries `background: #ffffff` so the dark
      # theme cannot make the QR unscannable.
      expect(response.body).to match(/background:\s*#ffffff/)
      # The wrapper sits inline so the page layout still flows.
      expect(response.body).to include("display: inline-block")
    end
  end

  describe "PATCH /settings/security/totp/confirm" do
    let(:seed) { "JBSWY3DPEHPK3PXP" }

    before do
      # Drive the controller's one-shot flash by going through enrollment.
      # We then override the user's seed to match the deterministic seed
      # the test computes a code against.
      post settings_security_totp_path
      user.update!(totp_seed_encrypted: seed)
      # P25 follow-up — F9. Reset the replay-defense watermark so a
      # prior test in this file's shared `let(:user)` does not block
      # this verify within the same 30-s step.
      user.update_columns(totp_last_used_step: nil)
      # Inject the deterministic seed into the flash so the confirm
      # action verifies against it.
      get settings_security_totp_show_path
    end

    it "stamps totp_enabled_at when the code is correct" do
      code = ROTP::TOTP.new(seed).now
      patch settings_security_totp_confirm_path, params: { code: code }
      # If the test's flash-keep machinery diverges, the controller
      # falls back to the user's seed (same seed) and confirms anyway.
      expect(user.reload.totp_enabled_at).to be_present
    end

    it "returns 422 when the code is wrong" do
      patch settings_security_totp_confirm_path, params: { code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.totp_enabled_at).to be_nil
    end
  end

  describe "GET /settings/security/totp/disable" do
    it "renders the action-screen when 2FA is on" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
      get settings_security_totp_disable_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("disable 2FA")
      # Bracketed-link inner-padding fix: label wrapped in <span class="bl">.
      expect(response.body).to include('[<span class="bl">disable 2FA</span>]')
    end

    it "asks for both password and TOTP code on the disable screen" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
      get settings_security_totp_disable_path
      expect(response.body).to include('name="password"')
      expect(response.body).to include('name="code"')
      expect(response.body).to include("password")
      expect(response.body).to include("authenticator app")
    end

    it "redirects to the status page when 2FA is already off" do
      get settings_security_totp_disable_path
      expect(response).to redirect_to(settings_security_totp_path)
    end
  end

  describe "POST /settings/security/totp/disable" do
    let(:seed) { "JBSWY3DPEHPK3PXP" }
    let(:password) { "password123" }

    before do
      user.update!(
        password: password,
        password_confirmation: password,
        totp_seed_encrypted: seed,
        totp_enabled_at: 1.hour.ago
      )
      # P25 follow-up — F9. Clear the replay watermark so each verify
      # in this `describe` block starts with a clean slate.
      user.update_columns(totp_last_used_step: nil)
    end

    it "disables 2FA when confirm=yes and both password + code are correct" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_disable_path,
           params: { confirm: "yes", password: password, code: code }
      expect(user.reload.totp_enabled?).to be false
      expect(user.reload.totp_disabled_at).to be_present
    end

    it "returns 422 when the code is wrong (password right)" do
      post settings_security_totp_disable_path,
           params: { confirm: "yes", password: password, code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.totp_enabled?).to be true
      expect(flash.now[:alert]).to include("credentials don't match")
    end

    it "returns 422 when the password is wrong (code right) and copy is generic" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_disable_path,
           params: { confirm: "yes", password: "nope", code: code }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.totp_enabled?).to be true
      # Generic copy — must not leak which field failed.
      expect(flash.now[:alert]).to include("credentials don't match")
      expect(flash.now[:alert]).not_to match(/password/i)
      expect(flash.now[:alert]).not_to match(/code|totp/i)
    end

    it "returns 422 when the password is blank" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_disable_path,
           params: { confirm: "yes", password: "", code: code }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.totp_enabled?).to be true
    end

    it "cancels and redirects when confirm != yes" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_disable_path,
           params: { confirm: "no", password: password, code: code }
      expect(response).to redirect_to(settings_security_totp_path)
      expect(user.reload.totp_enabled?).to be true
    end
  end

  describe "auth gate", :unauthenticated do
    it "redirects unauthenticated GETs to /login" do
      get settings_security_totp_path
      expect(response).to redirect_to(login_path)
    end

    it "redirects unauthenticated POSTs to /login" do
      post settings_security_totp_path
      expect(response).to redirect_to(login_path)
    end
  end
end
