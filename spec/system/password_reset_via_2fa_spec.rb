require "rails_helper"

# Phase 29 — Unit A2. The reset-password-via-2FA journey.
#
# A TOTP-configured user who forgot their password: visit
# `/password/reset`, prove possession of the second factor with a
# live code, set a new password, get redirected to `/login` (NOT
# auto-logged-in), then sign in fresh with the new password — passing
# the TOTP login challenge — and reach the app.
RSpec.describe "Password reset via 2FA", :unauthenticated, type: :system do
  before { driven_by(:rack_test) }

  before { Rack::Attack.cache.store.clear }

  # The reset marker mirrors its nonce in `Rails.cache` (same pattern
  # as `SessionsController::PRE_AUTH_COOKIE`). Test env's :null_store
  # would drop that write, so `load_reset_marker_user` would fail
  # closed on the set-password step and bounce back to `/password/reset`
  # — even though `create` verified the code. Swap to a real
  # MemoryStore so the nonce survives the create → edit hop, mirroring
  # `spec/system/totp_2fa_journey_spec.rb`.
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(memory_cache) }

  let(:old_password) { "forgotten-pass-1" }
  let(:new_password) { "remembered-pass-2" }
  let(:seed)         { "JBSWY3DPEHPK3PXP" }
  let!(:user) do
    create(
      :user,
      username: "resetter",
      password: old_password,
      password_confirmation: old_password,
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago
    )
  end

  it "resets the password with a 2FA code, then logs in fresh with the new password" do
    visit password_reset_path
    fill_in "username", with: "resetter"
    fill_in "code", with: ROTP::TOTP.new(seed).now
    click_button "[reset password]"

    # The code verified — on the set-password step now.
    expect(page).to have_current_path(edit_password_reset_path)

    fill_in "password", with: new_password
    fill_in "password_confirmation", with: new_password
    click_button "[set password]"

    # Redirected to /login, NOT auto-logged-in.
    expect(page).to have_current_path(login_path)
    expect(page).to have_content("password reset")

    # P25 follow-up — F9 replay defense. The reset step above verified
    # one live TOTP code and advanced the per-user `totp_last_used_step`
    # watermark. The login challenge below uses the SAME deterministic
    # seed; in a real flow the user would log in a fresh 30-s window
    # later. Clear the watermark to model that later window so the
    # second verification is not rejected as a same-step replay.
    user.update_columns(totp_last_used_step: nil)

    # The old password no longer works.
    fill_in "username", with: "resetter"
    fill_in "password", with: old_password
    click_button "[log in]"
    expect(page).to have_content("login failed")

    # The new password works — and the TOTP login challenge still
    # gates the configured user.
    fill_in "username", with: "resetter"
    fill_in "password", with: new_password
    click_button "[log in]"
    expect(page).to have_current_path(login_totp_path)

    # The login TOTP challenge renders `TotpCodeInputComponent` —
    # six unnamed visible boxes plus a hidden `<input name="code">`
    # that the `totp-code-input` Stimulus controller fills with the
    # concatenated 6-digit value on every keystroke. `rack_test`
    # does not execute Stimulus, so `fill_in "code"` cannot reach the
    # hidden field through the visible boxes. Set the hidden field
    # directly to model what the controller would have written.
    find('input[name="code"]', visible: :hidden).set(ROTP::TOTP.new(seed).now)
    click_button(match: :first)
    expect(page).to have_current_path(root_path)
  end
end
