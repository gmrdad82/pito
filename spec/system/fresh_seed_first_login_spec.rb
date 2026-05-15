require "rails_helper"

# Phase 29 — Unit A2 (R4). The fresh-seed first-login journey.
#
# On a fresh seed the owner has no TOTP and no `TrustedLocation` rows.
# Their very first login mints an active session directly (the
# first-login bootstrap — no pending-approval detour) and the
# post-session mandatory-2FA gate immediately forces them into TOTP
# setup. They cannot reach any other screen until enrollment is
# confirmed; once it is, the app opens up.
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

    # First-login bootstrap: an active session is minted directly and
    # the mandatory-2FA gate lands the user on the TOTP setup page.
    expect(page).to have_current_path(settings_security_totp_path)
    expect(Session.state_active.where(user_id: owner.id).count).to eq(1)

    bootstrap_row = LoginAttempt
                      .where(reason: LoginAttempt.reasons[:first_login_totp_setup_required])
                      .recent.first
    expect(bootstrap_row).to be_present
    expect(bootstrap_row.user_id).to eq(owner.id)

    # Trying to reach another screen bounces straight back to setup.
    visit channels_path
    expect(page).to have_current_path(settings_security_totp_path)

    # Complete enrollment: generate the seed, then confirm a code
    # computed from it.
    click_button "[enable 2FA]"
    expect(page).to have_content("enroll 2FA")

    seed = owner.reload.totp_seed_encrypted
    expect(seed).to be_present

    fill_in "code", with: ROTP::TOTP.new(seed).now
    click_button "[confirm 2FA]"
    expect(page).to have_content("2FA enrolled")

    # The gate has released — the previously-blocked route now loads.
    visit channels_path
    expect(page).to have_current_path(channels_path)
  end
end
