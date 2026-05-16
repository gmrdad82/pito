require "rails_helper"

# Phase 32 (settings refactor polish — Concern 2). Mandatory-2FA
# enrollment auto-opens on `/settings`.
#
# When the authenticated user has not yet configured TOTP, the gate
# redirects every non-allowlisted route to `/settings?enroll_totp=1`.
# `/settings` itself is allowlisted; it renders the page with:
#
#   * `.settings-panes--muted` on the outer pane wrapper.
#   * `aria-disabled="true"` on the outer pane wrapper.
#   * `data-controller="settings-modal"` carrying
#     `data-settings-modal-auto-open-url-value="/settings/security/totp"`
#     and `data-settings-modal-non-dismissible-value="yes"`.
#   * The bracketed `[close]` link inside the dialog header is
#     omitted (no JS surface to dismiss the modal).
#
# A TOTP-configured user sees the unmuted page with the standard
# closable modal harness (`non-dismissible-value="no"`,
# `auto-open-url-value=""`).
RSpec.describe "Settings — mandatory-2FA auto-open modal", type: :request do
  let(:password) { "supersecret123" }
  let(:seed)     { "JBSWY3DPEHPK3PXP" }

  describe "for an authenticated user with no TOTP configured", :unauthenticated do
    let(:user) do
      create(:user, password: password, password_confirmation: password)
    end

    before { sign_in_as(user) }

    it "renders /settings 200 even without the ?enroll_totp param" do
      get settings_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the muted-panes wrapper class on the outer pane stack" do
      get settings_path(enroll_totp: 1)
      expect(response.body).to include('class="settings-panes settings-panes--muted"')
      expect(response.body).to include('aria-disabled="true"')
    end

    it "renders the auto-open url + non-dismissible flags on the modal mount" do
      get settings_path(enroll_totp: 1)
      expect(response.body).to include(
        %(data-settings-modal-auto-open-url-value="#{settings_security_totp_path}")
      )
      expect(response.body).to include(
        'data-settings-modal-non-dismissible-value="yes"'
      )
    end

    it "renders the auto-open url + non-dismissible flags even WITHOUT the ?enroll_totp param" do
      # The render branch reads `Current.user.totp_configured?`, not
      # the query param — defense-in-depth so a direct hit (or a
      # cached redirect) still shows the gate's UI when warranted.
      get settings_path
      expect(response.body).to include(
        %(data-settings-modal-auto-open-url-value="#{settings_security_totp_path}")
      )
      expect(response.body).to include(
        'data-settings-modal-non-dismissible-value="yes"'
      )
    end

    it "omits the bracketed [close] link inside the modal header when non-dismissible" do
      get settings_path(enroll_totp: 1)
      # The dismissible flow renders `data-action="click->settings-modal#close"`
      # — that handle must be absent on the gate render. ERB escapes
      # `>` to `&gt;` in attribute values, so we match the encoded form.
      expect(response.body).not_to include('settings-modal#close')
    end

    it "leaves the modal-header title slot empty in mandatory mode" do
      # 2026-05-16 polish (Concern 1): the modal partial used to
      # pre-populate the header `<h2>` with "two-factor setup
      # required", which doubled up with the same headline inside
      # the Turbo Frame body. The header slot now stays empty in
      # mandatory mode — the body view's `<h1>` is the sole heading.
      get settings_path(enroll_totp: 1)
      expect(response.body).to include(
        '<h2 data-settings-modal-target="title" style="margin: 0;">&nbsp;</h2>'
      )
    end

    it "renders the 'two-factor setup required' headline inside the enrollment view body" do
      # The headline lives in the Turbo-Frame-fetched body
      # (`/settings/security/totp`), not on the `/settings` hub
      # response. Fetch the body directly.
      get settings_security_totp_path
      expect(response.body).to include("two-factor setup required")
    end
  end

  describe "for a TOTP-configured authenticated user", :unauthenticated do
    let(:user) do
      create(
        :user,
        password: password,
        password_confirmation: password,
        totp_seed_encrypted: seed,
        totp_enabled_at: 1.hour.ago
      )
    end

    before do
      user.update_columns(totp_last_used_step: nil, totp_disabled_at: nil)
      sign_in_as(user)
    end

    it "renders /settings 200 with the unmuted pane wrapper" do
      get settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('settings-panes--muted')
    end

    it "renders the standard (dismissible) modal harness — no auto-open url" do
      get settings_path
      expect(response.body).to include(
        'data-settings-modal-auto-open-url-value=""'
      )
      expect(response.body).to include(
        'data-settings-modal-non-dismissible-value="no"'
      )
    end

    it "keeps the [close] handle inside the modal header" do
      get settings_path
      # ERB-escaped `>` in the data-action attribute.
      expect(response.body).to include('settings-modal#close')
    end

    it "ignores the ?enroll_totp param when the user IS configured" do
      get settings_path(enroll_totp: 1)
      expect(response.body).not_to include('settings-panes--muted')
      expect(response.body).to include(
        'data-settings-modal-auto-open-url-value=""'
      )
      expect(response.body).to include(
        'data-settings-modal-non-dismissible-value="no"'
      )
    end
  end
end
