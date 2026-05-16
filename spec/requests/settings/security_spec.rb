require "rails_helper"

RSpec.describe "Settings::Security", type: :request do
  describe "GET /settings/security" do
    # Post-Phase-25 rollback. The dashboard collapsed to 2FA-status
    # only — the recent-activity panel, trusted-locations counter,
    # pending-sessions counter, auto-block list link, and per-attempts
    # link were dropped with the LoginAttempt + BlockedLocation +
    # TrustedLocation tables.

    it "renders the security pane with the 2FA status" do
      get settings_security_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("security")
      expect(response.body).to include("2FA")
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get settings_security_path
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include(login_path)
    end

    it "does not surface dropped surfaces (blocks / attempts panels)" do
      get settings_security_path
      expect(response.body).not_to include("active block")
      expect(response.body).not_to include("recent activity")
      expect(response.body).not_to match(%r{/settings/security/attempts})
      expect(response.body).not_to match(%r{/settings/security/blocks})
    end
  end
end
