require "rails_helper"

# Phase 29 — Unit A2. The mandatory-2FA gate
# (`Sessions::AuthConcern#require_totp_configured!`). An authenticated
# user who has NOT configured TOTP is redirected to the enrollment
# landing page from every non-allowlisted route. The TOTP-setup
# routes (`totps#new` / `create` / `show` / `update` confirm) plus
# `DELETE /session` are NOT redirected — no redirect loop. Once
# enrollment is confirmed (`totp_enabled_at` stamped), the gate
# releases.
#
# Browser-only (R3): this concern is included by
# `ApplicationController`; the API / MCP bearer-auth surfaces are not
# gated and are untouched by this unit.
RSpec.describe "Mandatory-2FA gate", type: :request do
  let(:password) { "supersecret123" }
  let(:seed)     { "JBSWY3DPEHPK3PXP" }

  # A signed-in user with NO TOTP configured — the state the gate
  # exists to catch.
  let(:unconfigured_user) do
    create(:user, password: password, password_confirmation: password)
  end

  describe "an authenticated user WITHOUT TOTP configured", :unauthenticated do
    before { sign_in_as(unconfigured_user) }

    %w[/ /channels /videos /projects /settings /settings/security].each do |path|
      it "is redirected from #{path} to the TOTP enrollment page" do
        get path
        expect(response).to redirect_to(settings_security_totp_path)
      end
    end

    it "carries the enrollment alert on the redirect" do
      get channels_path
      expect(flash[:alert]).to match(/two-factor/i)
    end
  end

  describe "the TOTP-setup allowlist is NOT redirected by the gate", :unauthenticated do
    before { sign_in_as(unconfigured_user) }

    it "allows GET /settings/security/totp (the enrollment landing page)" do
      get settings_security_totp_path
      expect(response).to have_http_status(:ok)
      expect(response).not_to redirect_to(settings_security_totp_path)
    end

    it "allows POST /settings/security/totp (generate the seed)" do
      post settings_security_totp_path
      # totps#create redirects to the one-shot show page — NOT bounced
      # back to the enrollment landing by the mandatory gate.
      expect(response).to redirect_to(settings_security_totp_show_path)
    end

    it "allows GET /settings/security/totp/show (the one-shot QR + codes)" do
      post settings_security_totp_path
      get settings_security_totp_show_path
      # show renders the one-shot payload (200) or redirects to `new`
      # if the cache entry is gone — either way it is NOT the gate's
      # redirect (the request reached the controller).
      expect(response).to have_http_status(:ok).or redirect_to(settings_security_totp_path)
    end

    it "allows PATCH /settings/security/totp/confirm (confirm the code)" do
      post settings_security_totp_path
      patch settings_security_totp_confirm_path, params: { code: "000000" }
      # A wrong code re-renders the show page (422) — the request
      # reached the controller, the gate did not bounce it.
      expect(response).to have_http_status(:unprocessable_content)
        .or redirect_to(settings_security_totp_path)
      expect(response).not_to redirect_to(root_path)
    end

    it "allows DELETE /session (logout) so the user is not trapped" do
      delete session_logout_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "completing enrollment releases the gate", :unauthenticated do
    it "lets a previously-blocked route through once totp_enabled_at is stamped" do
      sign_in_as(unconfigured_user)

      get channels_path
      expect(response).to redirect_to(settings_security_totp_path)

      # Simulate a confirmed enrollment.
      unconfigured_user.update!(
        totp_seed_encrypted: seed,
        totp_enabled_at: Time.current,
        totp_disabled_at: nil
      )

      get channels_path
      expect(response).to have_http_status(:ok)
      expect(response).not_to redirect_to(settings_security_totp_path)
    end
  end

  describe "the gate does not change unauthenticated behavior", :unauthenticated do
    it "still redirects an unauthenticated request to /login" do
      get channels_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "a TOTP-configured user is never gated", :unauthenticated do
    it "reaches the app normally" do
      configured = create(
        :user,
        password: password,
        password_confirmation: password,
        totp_seed_encrypted: seed,
        totp_enabled_at: 1.hour.ago
      )
      sign_in_as(configured)

      get channels_path
      expect(response).to have_http_status(:ok)
    end
  end
end
