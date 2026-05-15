require "rails_helper"

# Phase 12 — Step A (6a-sessions-and-login-ui.md) — Active Sessions UI.
# Phase 8 — tenant drop. Sessions are user-scoped only.
RSpec.describe "Settings::Sessions", type: :request do
  # Phase 29 — Unit A2. The mandatory-2FA gate redirects any
  # authenticated user who has not configured TOTP. These specs sign in
  # their own user, so it must be TOTP-configured to reach the actions
  # under test.
  let!(:user) { Current.user || create(:user, :totp_enabled) }
  let(:password) { "supersecret" }

  before do
    user.update!(password: password, password_confirmation: password)
  end

  describe "GET /settings/sessions" do
    it "lists the user's sessions" do
      sign_in_as(user)
      Session.create_for!(user: user, ip: "10.0.0.2", user_agent: "Other", remember: false)

      get settings_sessions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("user-agent")
      expect(response.body).to include("(this session)")
    end
  end

  describe "GET /settings/sessions/:id/revoke" do
    it "renders the action confirmation screen" do
      sign_in_as(user)
      other_record, _ = Session.create_for!(user: user, ip: "10.0.0.3", user_agent: "Other", remember: false)

      get revoke_settings_session_path(other_record)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[revoke]")
    end
  end

  describe "DELETE /settings/sessions/:id" do
    it "revokes a non-current session and redirects back to index" do
      sign_in_as(user)
      other_record, _ = Session.create_for!(user: user, ip: "10.0.0.3", user_agent: "Other", remember: false)

      delete settings_session_path(other_record)

      expect(response).to redirect_to(settings_sessions_path)
      expect(other_record.reload.revoked?).to be true
    end

    it "signs out and redirects to /login when revoking the current session" do
      current = sign_in_as(user)

      delete settings_session_path(current)

      expect(response).to redirect_to(login_path)
      expect(current.reload.revoked?).to be true
      expect(response.headers["Set-Cookie"].to_s).to include("#{Sessions::Authenticator::COOKIE_NAME}=;")
    end

    it "no-ops with a notice when the session is already revoked" do
      sign_in_as(user)
      already_revoked, _ = Session.create_for!(user: user, ip: "10.0.0.4", user_agent: "X", remember: false)
      already_revoked.revoke!

      delete settings_session_path(already_revoked)
      expect(response).to redirect_to(settings_sessions_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "user-boundary scoping" do
    it "does not surface another user's sessions in the index" do
      sign_in_as(user)

      other_user = create(:user)
      Session.create_for!(user: other_user, ip: "10.0.0.9", user_agent: "OtherUser", remember: false)

      get settings_sessions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("OtherUser")
    end

    it "raises RecordNotFound on revoke for a session belonging to another user" do
      sign_in_as(user)

      other_user = create(:user)
      other_record, _ = Session.create_for!(user: other_user, ip: "10.0.0.10", user_agent: "OtherUser", remember: false)

      get revoke_settings_session_path(other_record)
      expect(response).to have_http_status(:not_found)
    end
  end
end
