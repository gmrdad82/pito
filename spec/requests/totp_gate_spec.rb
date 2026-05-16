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

    # Phase 32 (settings refactor polish — Concern 2). The gate now
    # bounces every non-allowlisted route to `/settings?enroll_totp=1`
    # (the hub renders the auto-open modal on top of muted panes).
    # `/settings` itself is allowlisted so the redirect can land
    # without looping; `/settings/security` (and other settings
    # sub-pages) stay gated.
    %w[
      /
      /channels
      /videos
      /projects
      /games
      /bundles
      /calendar
      /settings/security
    ].each do |path|
      it "is redirected from #{path} to /settings?enroll_totp=1" do
        get path
        expect(response).to redirect_to(settings_path(enroll_totp: 1))
      end
    end

    it "carries the enrollment alert on the redirect" do
      get channels_path
      expect(flash[:alert]).to match(/two-factor/i)
    end

    it "renders /settings 200 (it is the gate's destination, not a redirect target)" do
      get settings_path
      expect(response).to have_http_status(:ok)
    end
  end

  # Phase 32 (settings refactor polish) — focused-dialog feel.
  # The enrollment landing page, when reached via the mandatory gate
  # (user has no TOTP configured), suppresses the nav header + footer
  # via `content_for(:hide_chrome, true)`. Once enrollment confirms,
  # the page re-renders with the normal chrome (for backup-codes /
  # disable management).
  describe "mandatory-gate enrollment view feels like a focused dialog", :unauthenticated do
    it "drops nav chrome and renders the dialog headline when the user is unconfigured" do
      sign_in_as(unconfigured_user)
      get settings_security_totp_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("two-factor setup required")
      # Header / footer nav-rows are gated by `unless content_for?(:hide_chrome)`.
      # The presence of the dialog-style copy plus the absence of the
      # nav-row markup is the contract.
      expect(response.body).not_to include('class="nav-row"')
      # The breadcrumb dot-list is also dropped (it sits above the page
      # heading on the configured branch).
      expect(response.body).not_to match(/breadcrumb/i)
    end

    # Phase 32 follow-up (2026-05-16). The "manage 2FA" page is gone.
    # A configured user who lands on `GET /settings/security/totp` is
    # redirected to root — there is no web-side surface for them.
    it "redirects an already-configured user away from the enrollment view" do
      configured = create(
        :user,
        password: password,
        password_confirmation: password,
        totp_seed_encrypted: seed,
        totp_enabled_at: 1.hour.ago
      )
      sign_in_as(configured)
      get settings_security_totp_path

      expect(response).to redirect_to(root_path)
    end

    # 2026-05-16 — the inline `[log out]` escape-hatch button was
    # dropped from the focused-dialog enrollment view alongside the
    # header [logout] removal. DELETE /session remains routable and is
    # still on the gate's allowlist (see the "TOTP-setup allowlist"
    # group below) for direct-URL / API / keyboard use; only the UI
    # affordance on this view was removed. Tab-close is the user-side
    # escape; admin reset via `pito:user:reset_totp` remains the
    # operator-side escape.
    it "does NOT render an inline logout form on the focused-dialog view" do
      sign_in_as(unconfigured_user)
      get settings_security_totp_path

      expect(response.body).not_to include('action="/session"')
      expect(response.body).not_to match(/name="_method"\s+value="delete"/)
    end
  end

  describe "the TOTP-setup allowlist is NOT redirected by the gate", :unauthenticated do
    # Phase 32 follow-up (2026-05-16). The web surface collapsed to a
    # single focused enrollment view (GET) + the atomic finalize
    # endpoint (POST). The previously-allowlisted `/show` GET and the
    # `/confirm` PATCH are gone.
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(memory_cache)
      sign_in_as(unconfigured_user)
    end

    it "allows GET /settings/security/totp (the enrollment view)" do
      get settings_security_totp_path
      expect(response).to have_http_status(:ok)
      expect(response).not_to redirect_to(settings_path(enroll_totp: 1))
    end

    it "allows POST /settings/security/totp (atomic finalize, wrong-code 422 path)" do
      get settings_security_totp_path
      post settings_security_totp_path, params: { code: "000000" }
      # A wrong code re-renders `new` at 422 — the request reached
      # the controller, the gate did not bounce it.
      expect(response).to have_http_status(:unprocessable_content)
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
      expect(response).to redirect_to(settings_path(enroll_totp: 1))

      # Simulate a confirmed enrollment.
      unconfigured_user.update!(
        totp_seed_encrypted: seed,
        totp_enabled_at: Time.current,
        totp_disabled_at: nil
      )

      get channels_path
      expect(response).to have_http_status(:ok)
      expect(response).not_to redirect_to(settings_path(enroll_totp: 1))
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
