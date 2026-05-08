require "rails_helper"

# Phase 12 — Step A (6a-sessions-and-login-ui.md) — Active Sessions UI.
RSpec.describe "Settings::Sessions", type: :request do
  let!(:user) { Current.user || create(:user, tenant: Current.tenant) }
  let(:password) { "supersecret" }

  before do
    user.update!(password: password, password_confirmation: password)
  end

  describe "GET /settings/sessions" do
    it "lists the user's sessions" do
      sign_in_as(user)
      # Mint a second session so the index has more than one row.
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

  # Phase 7.5 — Step 01 hygiene sweep. Regression coverage for the removal
  # of the `.unscoped + where(user_id: …)` pattern. The natural
  # `Current.user.sessions` association is strictly more restrictive than
  # the workaround it replaced — it filters by both `user_id` (association)
  # AND `tenant_id` (BelongsToTenant default scope). These specs assert
  # both legs of that filter.
  describe "cross-boundary scoping" do
    it "does not surface another user's sessions in the index" do
      sign_in_as(user)

      other_user = create(:user, tenant: Current.tenant)
      other_record, _ = Session.create_for!(user: other_user, ip: "10.0.0.9", user_agent: "OtherUser", remember: false)

      get settings_sessions_path
      expect(response).to have_http_status(:ok)
      # Use the unique `user_agent` string as the rendered-row marker
      # — checking for the bare numeric id is brittle (small integers
      # appear in many incidental contexts: widths, color hexes, etc.).
      expect(response.body).not_to include("OtherUser")
    end

    it "raises RecordNotFound on revoke for a session belonging to another user" do
      sign_in_as(user)

      other_user = create(:user, tenant: Current.tenant)
      other_record, _ = Session.create_for!(user: other_user, ip: "10.0.0.10", user_agent: "OtherUser", remember: false)

      get revoke_settings_session_path(other_record)
      expect(response).to have_http_status(:not_found)
    end

    it "raises RecordNotFound on destroy for a session belonging to another tenant" do
      sign_in_as(user)

      # Build a row that shares user_id with the current user but lives in
      # a different tenant — the kind of row the BelongsToTenant default
      # scope is supposed to hide. Use `unscoped` to bypass our own scope
      # at write time so we can plant the rogue row.
      other_tenant = create(:tenant, slug: "rogue-#{SecureRandom.hex(2)}")
      rogue_session = Session.unscoped.create!(
        user: user,
        tenant: other_tenant,
        token_digest: Pito::TokenDigest.call("rogue-#{SecureRandom.hex(8)}"),
        ip: "10.9.9.9",
        user_agent: "RogueAgent",
        remember: false,
        last_activity_at: Time.current
      )

      delete settings_session_path(rogue_session)
      expect(response).to have_http_status(:not_found)
      expect(rogue_session.reload.revoked?).to be(false)
    end
  end
end
