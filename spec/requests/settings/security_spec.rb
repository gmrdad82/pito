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

    it "links to the full attempts list when there is at least one attempt", :unauthenticated do
      # Phase 29 — Unit A2. `:unauthenticated` skips the auto-sign-in, so
      # this spec mints + signs in its own user. The mandatory-2FA gate
      # would bounce a non-TOTP user to the enrollment page, so the user
      # must be TOTP-configured to reach the security pane.
      user = User.first || create(:user, :totp_enabled)
      sign_in_as(user)
      # 2026-05-11 — the muted intro paragraph (which used to surface
      # the [attempts] link unconditionally) was dropped per user
      # direction. The recent-activity panel still renders the
      # `[ all attempts ]` bracketed link, but only when at least one
      # attempt exists — otherwise the empty state copy + the
      # `[ auto-block list ]` link replace it.
      create(:login_attempt)
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

    # 2026-05-11 — per user direction the muted intro block
    # ("every login attempt is logged. suspicious activity surfaces
    # here and on [attempts]. 2FA enrollment lands later in this
    # phase.") was dropped from the security dashboard. The 2FA
    # surface shipped in Phase 25 01e so the "lands later" copy is
    # also stale.
    it "no longer renders the muted intro block under the security H1" do
      get settings_security_path
      expect(response.body).not_to include("every login attempt is logged")
      expect(response.body).not_to include("2FA enrollment lands later")
      expect(response.body).not_to include("suspicious activity surfaces here")
    end
  end
end
