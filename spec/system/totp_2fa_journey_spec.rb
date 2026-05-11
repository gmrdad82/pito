require "rails_helper"

# Phase 25 — 01e. End-to-end TOTP 2FA happy + sad + edge paths.
RSpec.describe "TOTP 2FA journey", type: :system do
  before { driven_by(:rack_test) }

  let(:password) { "password123" }
  let(:user) { @auto_signed_in_user }

  context "happy path: enroll → confirm → manage" do
    it "enrolls, confirms with a fresh code, then disables" do
      visit "/settings/security/totp"
      expect(page).to have_content("[ enable 2FA ]")

      click_button "[ enable 2FA ]"

      expect(page).to have_content("enroll 2FA")
      expect(page).to have_content("scan")
      expect(page).to have_content("backup codes")

      seed = user.reload.totp_seed_encrypted
      expect(seed).to be_present
      expect(user.totp_backup_codes.count).to eq(10)

      code = ROTP::TOTP.new(seed).now
      fill_in "code", with: code
      click_button "[ confirm 2FA ]"

      expect(page).to have_content("2FA enrolled")
      expect(user.reload.totp_enabled?).to be true
    end
  end

  context "sad path: wrong TOTP code during confirm" do
    it "renders an error and keeps enrollment pending" do
      visit "/settings/security/totp"
      click_button "[ enable 2FA ]"

      expect(page).to have_content("enroll 2FA")

      fill_in "code", with: "000000"
      click_button "[ confirm 2FA ]"

      expect(page).to have_content("login failed")
      # The user has been seeded (seed + 10 codes) but `totp_enabled_at`
      # only flips on a successful confirm. `User#totp_enabled?` is the
      # canonical truth check for "2FA is on" — see Phase 25 — 01e
      # spec — but the FRESH-CONFIRM gate is `totp_enabled_at`.
      expect(user.reload.totp_enabled_at).to be_nil
    end
  end

  context "manage: regenerate backup codes consumes the action-screen pattern" do
    before do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
      user.totp_backup_codes.create!(code_digest: BCrypt::Password.create("OLDCODE2"))
    end

    it "regenerates 10 fresh codes via the action-screen confirmation" do
      visit "/settings/security/totp_backup_codes"
      expect(page).to have_content("unused")

      click_link "[regenerate]"
      expect(page).to have_content("regenerate backup codes")

      code = ROTP::TOTP.new("JBSWY3DPEHPK3PXP").now
      fill_in "code", with: code
      click_button "[ regenerate ]"

      expect(page).to have_content("new codes")
      expect(user.reload.totp_backup_codes.count).to eq(10)
    end
  end
end
