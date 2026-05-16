require "rails_helper"

# Phase 32 (settings refactor polish) — Concern 1.
#
# The new /settings Row 1 Left profile pane PATCHes
# `Settings::UserController#update`. The controller already mounts
# `RecentTotpVerification`; the partial form mounts the
# `totp-modal` Stimulus controller wiring; the layout mounts the
# shared TOTP verification modal for every authenticated user.
#
# This spec locks the contract end-to-end on the inline /settings
# pane: when the user submits the profile form on the dashboard, a
# fresh `totp_code` is required to authorize the change, and the
# response feedback is the generic flash on rejection. The JS
# modal-opening behavior itself is covered by manual validation —
# `rack_test` has no JavaScript runtime; the round-trip is simulated
# here by posting the form with the `totp_code` parameter the JS
# modal would inject.
#
# 2026-05-16 — recent-TOTP gate scope narrowed to this surface
# (`Settings::UserController#update`). The Slack + Discord webhook
# panes lost the gate and now save plainly.
RSpec.describe "Settings profile pane — recent-TOTP gate",
               :unauthenticated, type: :system do
  before { driven_by(:rack_test) }

  let(:password) { "lucy-password-1" }
  let(:seed)     { "JBSWY3DPEHPK3PXP" }
  let!(:user) do
    create(
      :user,
      username: "lucy",
      password: password,
      password_confirmation: password,
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago
    )
  end

  before do
    # Replay-defense watermark reset so each example consumes a fresh
    # code window without interference.
    user.update_columns(totp_last_used_step: nil, totp_disabled_at: nil)
    sign_in_capybara_as(user)
  end

  it "renders the profile form on /settings with totp-modal wiring" do
    visit settings_path
    expect(page).to have_content("profile")
    # Form posts to /settings/user with the totp-modal controller
    # mounted so the layout-level dialog intercepts the submit when
    # 2FA is on.
    form = page.find("form[action='/settings/user']")
    expect(form["data-controller"]).to include("totp-modal")
    expect(form["data-totp-modal-required-value"]).to eq("yes")
  end

  it "rejects the profile update with the generic flash when no totp_code is supplied" do
    original_username = user.username

    # Patch the endpoint directly (simulates the unintercepted
    # rack_test submit — equivalent to the user clicking `[update]`
    # without the JS modal collecting a code).
    page.driver.submit :patch, settings_user_path, {
      user: {
        username: "lucy_updated",
        current_password: password,
        password: "",
        password_confirmation: ""
      }
    }

    expect(page.driver.status_code).to eq(422)
    expect(page.body).to include("credentials don").and include("match")
    expect(user.reload.username).to eq(original_username)
  end

  it "rejects the profile update when the totp_code is wrong" do
    original_username = user.username

    page.driver.submit :patch, settings_user_path, {
      user: {
        username: "lucy_updated",
        current_password: password,
        password: "",
        password_confirmation: ""
      },
      totp_code: "000000"
    }

    expect(page.driver.status_code).to eq(422)
    expect(page.body).to include("credentials don").and include("match")
    expect(user.reload.username).to eq(original_username)
  end

  it "accepts the profile update when the totp_code is correct (simulates modal auto-submit)" do
    new_username = "lucy_#{SecureRandom.hex(3)}"

    page.driver.submit :patch, settings_user_path, {
      user: {
        username: new_username,
        current_password: password,
        password: "",
        password_confirmation: ""
      },
      totp_code: ROTP::TOTP.new(seed).now
    }

    # rack_test's `submit` follows the 302 → /settings, so the
    # observable signals are the final `current_path` and the
    # database mutation. A failure-path 422 would land us back on
    # `/settings/user` with a re-rendered form; we assert neither
    # form re-render nor 422 markup is present.
    expect(page.driver.status_code).to eq(200)
    expect(URI.parse(current_url).path).to eq(settings_path)
    expect(page.body).not_to include("credentials don")
    expect(user.reload.username).to eq(new_username)
  end

  private

  # Mint a session row for the named user and inject the signed cookie
  # into the Capybara session. Mirrors the hand-roll in
  # `spec/support/auth.rb` — kept inline here because the spec is
  # `:unauthenticated` (we opt out of the auto-hook to control the
  # signed-in identity).
  def sign_in_capybara_as(target_user)
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
