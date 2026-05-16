require "rails_helper"

# Phase 29 — Unit A2 (R4). The fresh-seed first-login journey.
#
# On a fresh seed the owner has no TOTP. Their very first login mints
# an active session directly (the first-login bootstrap) and the
# post-session mandatory-2FA gate immediately forces them into TOTP
# setup. They cannot reach any other screen until enrollment is
# confirmed; once it is, the app opens up.
#
# Post-Phase-25 rollback: there is no per-attempt LoginAttempt row.
RSpec.describe "Fresh-seed first login", :unauthenticated, type: :system do
  before { driven_by(:rack_test) }

  # The TOTP one-shot enrollment payload lives in `Rails.cache`; the
  # test env's :null_store would drop it and break the enroll → show
  # chain. Swap in a real MemoryStore.
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }
  before { allow(Rails).to receive(:cache).and_return(memory_cache) }

  let(:password) { "owner-password-1" }
  let!(:owner) do
    # Stand in for the seeded owner: a User with no TOTP configured.
    create(:user, username: "owner", password: password, password_confirmation: password)
  end

  it "logs in, is gated into TOTP setup, cannot escape, completes enrollment, then reaches the app" do
    visit login_path
    fill_in "username", with: "owner"
    fill_in "password", with: password
    click_button "[log in]"

    # Phase 32 (settings refactor polish — Concern 2). First-login
    # bootstrap mints an active session and lands the user on the
    # settings hub with `?enroll_totp=1`; the page renders the muted
    # panes underneath and the modal-mount markup that auto-opens
    # the TOTP enrollment modal on connect. rack_test cannot execute
    # the Stimulus connect, so we assert the gate's contract at the
    # markup level (auto-open + non-dismissible attributes), plus
    # that the auto-loaded URL is the enrollment landing.
    expect(page).to have_current_path(settings_path(enroll_totp: 1))
    expect(Session.state_active.where(user_id: owner.id).count).to eq(1)

    expect(page.body).to include('class="settings-panes settings-panes--muted"')
    expect(page).to have_css(
      "[data-controller='settings-modal']" \
      "[data-settings-modal-auto-open-url-value='#{settings_security_totp_path}']" \
      "[data-settings-modal-non-dismissible-value='yes']"
    )

    # Trying to reach another screen bounces straight back to the
    # hub (with the modal-mount markup still on).
    visit channels_path
    expect(page).to have_current_path(settings_path(enroll_totp: 1))
    expect(page).to have_css(
      "[data-settings-modal-non-dismissible-value='yes']"
    )

    # Phase 32 follow-up (2026-05-16). 2FA / TOTP cleanup. Enrollment
    # collapsed to a single atomic step — the view renders the QR +
    # codes + the 6-digit input together; clicking `[ enable 2FA ]`
    # with a valid code finalizes in one transaction.
    #
    # The seed lives in `Rails.cache` (the draft), NOT on the user
    # row, until the atomic confirm. Read it from the cache to
    # compute a valid TOTP code for the submit.
    visit settings_security_totp_path
    expect(page).to have_content("two-factor setup required")
    expect(page.body).not_to include('class="nav-row"')

    draft_key = Settings::Security::TotpsController
                  .enrollment_cache_key(owner.id)
    draft = memory_cache.read(draft_key)
    expect(draft).to be_present
    seed = draft[:seed]
    expect(seed).to be_present

    # The user row is still untouched at this point (atomic-finalize
    # contract).
    expect(owner.reload.totp_seed_encrypted).to be_nil
    expect(owner.totp_backup_codes.count).to eq(0)

    fill_in "code", with: ROTP::TOTP.new(seed).now
    click_button "[enable 2FA]"

    # The atomic finalize transaction now ran: seed persisted, 10
    # backup codes persisted, `totp_enabled_at` stamped.
    expect(owner.reload.totp_seed_encrypted).to eq(seed)
    expect(owner.totp_enabled?).to be(true)
    expect(owner.totp_backup_codes.count).to eq(10)

    # The gate has released — the previously-blocked route now loads
    # and the regular nav chrome is back.
    visit channels_path
    expect(page).to have_current_path(channels_path)
    expect(page.body).to include('class="nav-row"')

    # And /settings now renders without the muted-panes treatment +
    # without the auto-open modal markup.
    visit settings_path
    expect(page.body).not_to include("settings-panes--muted")
    expect(page).to have_css(
      "[data-settings-modal-auto-open-url-value='']"
    )
  end
end
