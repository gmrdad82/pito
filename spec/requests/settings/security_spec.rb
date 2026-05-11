require "rails_helper"

RSpec.describe "Settings::Security", type: :request do
  describe "GET /settings/security" do
    it "renders the security pane with the 2FA status (off in 01a)" do
      get settings_security_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("security")
      expect(response.body).to include("2FA")
      expect(response.body).to include("off")
    end

    it "renders recent activity counts" do
      create(:login_attempt)
      create(:login_attempt, :blocked)

      get settings_security_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("active block")
      expect(response.body).to match(/failed/i)
    end

    it "links to the full attempts list", :unauthenticated do
      user = User.first || create(:user)
      sign_in_as(user)
      get settings_security_path
      expect(response.body).to include("/settings/security/attempts")
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get settings_security_path
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include(login_path)
    end

    # Phase 25 — 01b. Adds trusted-locations + pending counters.
    it "renders trusted-locations + pending counters" do
      user = User.first || create(:user)
      create(:trusted_location, user: user)
      create(:session, :pending, user: user)
      get settings_security_path
      expect(response.body).to include("trusted locations")
      expect(response.body).to include("pending")
    end
  end
end
