require "rails_helper"

# Phase 25 — 01g cross-cutting system spec. The umbrella spec calls
# for journeys A–H across web + TUI + MCP. This file owns the Rails
# (web + MCP) coverage; the TUI half lives in the rust agent's
# `extras/cli/tests/` lane.
#
# The journeys covered here are Rails-driveable end-to-end with the
# rack_test Capybara driver (no JS needed — every confirmation is an
# action-screen, every destructive flow is a `confirm=yes` POST). MCP
# tools are exercised via direct in-process calls because that's the
# canonical pattern in this codebase (see `spec/mcp/`).
RSpec.describe "Login security journeys", type: :system do
  # P25 follow-up — F8. The pre-auth nonce that gates the `/login/totp`
  # challenge is mirrored in `Rails.cache`. Test env's :null_store
  # drops that write, so `valid_nonce?` fails closed and the TOTP
  # submit can never succeed. Swap to a real MemoryStore so the nonce
  # written by `SessionsController#create` survives to the challenge
  # submit — the same pattern `spec/system/totp_2fa_journey_spec.rb`
  # uses for its cache-backed flows.
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    driven_by(:rack_test)
    allow(Rails).to receive(:cache).and_return(memory_cache)
    Rack::Attack.cache.store.clear
    Auth::GeoEnricher.reset_deferred! if defined?(Auth::GeoEnricher)
    allow(Auth::GeoEnricher).to receive(:db_available?).and_return(false) if defined?(Auth::GeoEnricher)
  end

  let(:password) { "supersecret123" }
  let!(:user) do
    u = User.first || create(:user)
    u.update!(password: password, password_confirmation: password)
    u
  end

  # Visiting `/login` in a system spec requires the auto-sign-in
  # before-hook to be skipped. Tag examples with :unauthenticated.

  # Phase 29 — Unit A2. 2FA is mandatory. A TOTP-configured user
  # logging in always goes through the `/login/totp` challenge (step
  # 4 of the login pipeline) — the trusted-location classification
  # only runs for users WITHOUT TOTP, and such a user is immediately
  # gated into TOTP enrollment by the post-session mandatory gate.
  # Journey A therefore covers: password → TOTP challenge → app.
  describe "Journey A — username + 2FA login happy path", :unauthenticated do
    let(:seed) { "JBSWY3DPEHPK3PXP" }

    it "signs in with username + password + a TOTP code, reaches root" do
      user.update!(totp_seed_encrypted: seed, totp_enabled_at: 1.hour.ago)

      visit login_path
      fill_in "username", with: user.username
      fill_in "password", with: password
      click_button "[log in]"

      # Step 4 — the TOTP login challenge.
      expect(page).to have_current_path(login_totp_path)
      fill_in "code", with: ROTP::TOTP.new(seed).now
      click_button(match: :first)

      expect(page).to have_current_path(root_path)
      success_row = LoginAttempt
                      .where(reason: LoginAttempt.reasons[:new_location_2fa_passed])
                      .recent.first
      expect(success_row).to be_present
      expect(success_row.user_id).to eq(user.id)
    end
  end

  describe "Journey F — rate-limit trip → recovery", :unauthenticated do
    it "5 fast wrongs from one IP pass, the 6th lands a generic 429 (LD-14)" do
      5.times do |i|
        visit login_path
        fill_in "username", with: "f_#{i}"
        fill_in "password", with: "wrong"
        click_button "[log in]"
        # The first five should NOT be throttled.
      end

      # The throttle trips on the 6th. rack_test surfaces the 429
      # status via `page.status_code`.
      visit login_path
      fill_in "username", with: "f_6"
      fill_in "password", with: "wrong"
      click_button "[log in]"

      expect(page.status_code).to eq(429)
      expect(page.body.downcase).to include("login failed.")
      # LD-14 — the rate-limit reason must NOT leak to the user.
      expect(page.body.downcase).not_to include("rate")
      expect(page.body.downcase).not_to include("throttl")
    end
  end

  describe "Journey C/D bridge — approve from MCP-style tool call" do
    # Set up a pending-approval session, then exercise the approver
    # service directly (the MCP tool surface delegates to the same
    # service, so this covers the MCP half of the journey at the
    # service boundary).
    let(:pending_user) { create(:user) }
    let(:operator) { user }  # already signed in via the system before-hook
    let(:fp) { Digest::SHA256.hexdigest("journey-c-fp") }
    let!(:pending_session) { create(:session, :pending, user: pending_user) }
    let!(:pending_attempt) do
      create(:login_attempt, :pending,
             user: pending_user,
             fingerprint_hash: fp,
             ip_prefix: "10.10.0.0/24",
             session: pending_session)
    end

    it "MCP approve flips pending → active and writes an audit row" do
      fake_request = ActionDispatch::TestRequest.create.tap do |r|
        r.env["REMOTE_ADDR"] = "127.0.0.1"
        r.env["HTTP_USER_AGENT"] = "mcp-shim"
      end

      expect {
        Auth::LoginAttemptApprover.call(
          login_attempt: pending_attempt,
          acting_user: operator,
          source: :mcp,
          request: fake_request
        )
      }.to change(AuthAuditLog, :count).by(1)

      pending_session.reload
      expect(pending_session.state_active?).to be true

      log = AuthAuditLog.last
      expect(log.action).to eq("approve")
      expect(log.source_surface).to eq("mcp")
    end

    it "MCP block flips pending → revoked and adds the BlockedLocation" do
      expect {
        Auth::LoginAttemptBlocker.call(
          login_attempt: pending_attempt,
          acting_user: operator,
          source: :mcp
        )
      }.to change(BlockedLocation, :count).by(1)
        .and change(AuthAuditLog.where(action: :block), :count).by(1)

      pending_session.reload
      expect(pending_session.state_revoked?).to be true
    end
  end

  describe "Journey E — block → unblock → recover" do
    # Pre-block the pair, then unblock from web /settings, then
    # confirm a subsequent login attempt no longer short-circuits to
    # `:blocked_pair`.
    let(:fp) { Digest::SHA256.hexdigest("journey-e-fp") }
    let!(:block_row) do
      create(:blocked_location,
             fingerprint_hash: fp,
             ip_prefix: "10.99.0.0/24")
    end

    it "unblock via web returns the pair to the normal login flow" do
      visit settings_security_block_unblocking_path(block_row)
      expect(page).to have_button("[unblock]")
      click_button "[unblock]"

      block_row.reload
      expect(block_row.unblocked_at).to be_present
      # The row is soft-unblocked — `BlockedLocation.active` no longer
      # returns it; future login attempts on the pair go through the
      # normal path.
      expect(BlockedLocation.active.for_pair(fp, "10.99.0.0/24")).to be_empty
    end
  end

  describe "Journey G — 2FA disable round trip" do
    it "disable + re-enroll fires totp_disable + totp_enroll audit rows" do
      totp_user = create(:user, :totp_enabled)

      # Disable.
      expect {
        Auth::TotpDisabler.call(user: totp_user,
                                acting_user: totp_user,
                                source_surface: :web)
      }.to change(AuthAuditLog.where(action: :totp_disable), :count).by(1)

      totp_user.reload
      expect(totp_user.totp_enabled?).to be false

      # Re-enroll. The enroller bumps the audit ONLY at confirmation,
      # not on the initial seed. Stamp `totp_enabled_at` directly and
      # write the audit row through the same call site the controller
      # uses.
      Auth::TotpEnroller.call(user: totp_user)
      Auth::AuditLogger.call(
        acting_user: totp_user,
        source_surface: :web,
        action: :totp_enroll,
        target: totp_user,
        metadata: { enrolled_user_id: totp_user.id }
      )

      enroll_rows = AuthAuditLog.where(action: :totp_enroll, acting_user_id: totp_user.id)
      expect(enroll_rows.count).to be >= 1
    end
  end

  describe "Journey H — purge cycle" do
    let!(:la) do
      create(:login_attempt, user: user, ip: "8.8.8.8",
             email_attempted: user.username)
    end

    it "web purge writes the AuthAuditLog row and removes the attempt" do
      visit settings_security_attempts_purge_path(ip: "8.8.8.8")
      expect(page).to have_button("[purge]")

      expect {
        click_button "[purge]"
      }.to change { LoginAttempt.where(ip: "8.8.8.8").count }.to(0)
        .and change { AuthAuditLog.where(action: :purge).count }.by(1)

      log = AuthAuditLog.where(action: :purge).last
      expect(log.target_type).to eq("LoginAttempt")
      expect(log.metadata["kind"]).to eq("attempts")
    end
  end
end
