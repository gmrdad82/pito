require "rails_helper"

# Phase 32 (settings refactor polish — Concern 2). System-level
# regression coverage for the mandatory-2FA enrollment gate's
# settings-hub rendering.
#
# rack_test cannot execute the Stimulus `connect()` that would
# `dialog.showModal()` or attach the non-dismissible behavior at
# runtime; we cover the contract by asserting the static markup
# the controller will consume on connect, plus the route-level
# bounce behavior end-to-end.
RSpec.describe "Settings — mandatory-2FA enrollment gate (system shell)",
               :unauthenticated, type: :system do
  before { driven_by(:rack_test) }

  let(:password) { "lucy-password-1" }
  let(:seed)     { "JBSWY3DPEHPK3PXP" }

  let!(:unconfigured_user) do
    create(:user, username: "lucy", password: password, password_confirmation: password)
  end

  context "without TOTP configured" do
    before { sign_in_as(unconfigured_user) }

    it "lands on /settings with the muted-panes + auto-open + non-dismissible markup" do
      visit settings_path(enroll_totp: 1)

      expect(page).to have_current_path(settings_path(enroll_totp: 1))
      expect(page.body).to include('class="settings-panes settings-panes--muted"')
      expect(page.body).to include('aria-disabled="true"')

      expect(page).to have_css(
        "[data-controller='settings-modal']" \
        "[data-settings-modal-auto-open-url-value='#{settings_security_totp_path}']" \
        "[data-settings-modal-non-dismissible-value='yes']"
      )
    end

    it "renders the 'two-factor setup required' headline inside the enrollment view body" do
      # 2026-05-16 polish (Concern 1): the modal header `<h2>` slot
      # stays empty in mandatory mode to avoid doubling up with the
      # `<h1>` headline inside the Turbo-Frame body. We assert the
      # body view directly — it is what loads into the dialog frame
      # on Stimulus connect.
      visit settings_security_totp_path
      expect(page.body).to include("two-factor setup required")
    end

    it "drops the [close] dismiss link from the modal header" do
      visit settings_path(enroll_totp: 1)
      # The dismissible flow renders a `data-action` pointing at
      # `settings-modal#close`; the non-dismissible flow omits the
      # whole link.
      expect(page.body).not_to include("settings-modal#close")
    end

    it "bounces every domain route back to /settings?enroll_totp=1" do
      visit channels_path
      expect(page).to have_current_path(settings_path(enroll_totp: 1))

      visit videos_path
      expect(page).to have_current_path(settings_path(enroll_totp: 1))

      visit settings_security_path
      expect(page).to have_current_path(settings_path(enroll_totp: 1))
    end

    it "renders /settings 200 even WITHOUT the ?enroll_totp param (defense in depth)" do
      visit settings_path
      expect(page).to have_current_path(settings_path)
      expect(page.body).to include("settings-panes--muted")
    end

    it "still allows the TOTP enrollment routes to render directly" do
      visit settings_security_totp_path
      expect(page).to have_current_path(settings_security_totp_path)
      expect(page).to have_content("two-factor setup required")
    end

    it "still allows the logout route" do
      page.driver.submit :delete, session_logout_path, {}
      expect(page).to have_current_path(login_path)
    end
  end

  context "with TOTP configured" do
    let!(:configured_user) do
      create(
        :user,
        username: "lucy-2fa",
        password: password,
        password_confirmation: password,
        totp_seed_encrypted: seed,
        totp_enabled_at: 1.hour.ago
      )
    end

    before do
      configured_user.update_columns(totp_last_used_step: nil, totp_disabled_at: nil)
      sign_in_as(configured_user)
    end

    it "renders /settings unmuted with the closable modal harness" do
      visit settings_path
      expect(page).to have_current_path(settings_path)
      expect(page.body).not_to include("settings-panes--muted")
      expect(page).to have_css(
        "[data-controller='settings-modal']" \
        "[data-settings-modal-auto-open-url-value='']" \
        "[data-settings-modal-non-dismissible-value='no']"
      )
    end

    it "navigates to /channels freely" do
      visit channels_path
      expect(page).to have_current_path(channels_path)
    end
  end

  private

  def sign_in_as(target_user)
    _record, plaintext = Session.create_for!(
      user: target_user,
      ip: "127.0.0.1",
      user_agent: "RspecSystem"
    )

    seed_request = ActionDispatch::TestRequest.create
    jar = ActionDispatch::Cookies::CookieJar.build(seed_request, {})
    jar.signed[Sessions::Authenticator::COOKIE_NAME] = plaintext
    raw = jar[Sessions::Authenticator::COOKIE_NAME.to_s]

    Capybara.current_session.driver.browser.set_cookie(
      "#{Sessions::Authenticator::COOKIE_NAME}=#{raw}; path=/"
    )
  end
end
