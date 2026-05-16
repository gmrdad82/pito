require "rails_helper"

# 2026-05-16 (sessions revamp v2). The standalone `/settings/sessions`
# index + per-row revoke surfaces are GONE. The sessions table now
# renders INLINE in the Security pane on `/settings`. The bulk-revoke
# action endpoint (`/settings/sessions/revokes/:ids`) stays as the
# single revoke entry point per the bulk-as-foundation rule.
#
# 2026-05-16 (sessions revamp v3 — modal-confirm). The GET
# confirmation screen (action-screen page) is GONE. Confirmation is
# now an in-page `<dialog>` mounted on the Security pane and
# populated client-side by the `sessions-bulk-revoke` Stimulus
# controller. Only the POST endpoint survives.
#
# Coverage in this file:
#
#   * POST /settings/sessions/revokes/:ids — actual revoke.
#   * Defense-in-depth routing assertions for the dropped surfaces.
#
# Inline-table-on-Security-pane + modal-mount assertions live alongside
# the `/settings` request spec (`spec/requests/settings_spec.rb`); the
# pane partial itself has a focused view spec.
RSpec.describe "Settings::Sessions", type: :request do
  # Phase 29 — Unit A2. The mandatory-2FA gate redirects any
  # authenticated user who has not configured TOTP. These specs sign
  # in their own user, so it must be TOTP-configured to reach the
  # actions under test.
  let!(:user) { Current.user || create(:user, :totp_enabled) }
  let(:password) { "supersecret" }

  before do
    user.update!(password: password, password_confirmation: password)
  end

  describe "POST /settings/sessions/revokes/:ids" do
    it "revokes every targeted session and redirects to /settings with laconic flash" do
      sign_in_as(user)
      a, _ = Session.create_for!(user: user, ip: "10.0.0.40", user_agent: "A")
      b, _ = Session.create_for!(user: user, ip: "10.0.0.41", user_agent: "B")

      post settings_sessions_bulk_revoke_path(ids: [ a.id, b.id ].join(",")), params: { confirm: "yes" }

      expect(response).to redirect_to(settings_path)
      expect(a.reload.revoked?).to be true
      expect(b.reload.revoked?).to be true
      # 2026-05-16 (sessions revamp v3) — shortened flash copy.
      # Compare to other pito laconic flashes (`channel starred`,
      # `notifications cleared`); no terminal period, no "was
      # successfully" filler.
      expect(flash[:notice]).to eq("2 sessions revoked")
    end

    it "drops the count entirely for a single-element bulk (count of 1 is implied)" do
      sign_in_as(user)
      a, _ = Session.create_for!(user: user, ip: "10.0.0.50", user_agent: "Solo")

      post settings_sessions_bulk_revoke_path(ids: a.id.to_s), params: { confirm: "yes" }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to eq("session revoked")
    end

    it "signs out and bounces to /login when the current session is in the set — no flash notice" do
      current = sign_in_as(user)
      other, _ = Session.create_for!(user: user, ip: "10.0.0.42", user_agent: "Other")

      post settings_sessions_bulk_revoke_path(ids: [ current.id, other.id ].join(",")), params: { confirm: "yes" }

      expect(response).to redirect_to(login_path)
      expect(current.reload.revoked?).to be true
      expect(other.reload.revoked?).to be true
      expect(response.headers["Set-Cookie"].to_s).to include("#{Sessions::Authenticator::COOKIE_NAME}=;")
      # The login page already implies signed-out state; no notice.
      expect(flash[:notice]).to be_blank
    end

    it "skips already-revoked rows in the input list and reports the live count only" do
      sign_in_as(user)
      already_revoked, _ = Session.create_for!(user: user, ip: "10.0.0.43", user_agent: "X")
      already_revoked.revoke!
      live, _ = Session.create_for!(user: user, ip: "10.0.0.44", user_agent: "Y")

      expect {
        post settings_sessions_bulk_revoke_path(ids: [ already_revoked.id, live.id ].join(",")), params: { confirm: "yes" }
      }.not_to raise_error

      expect(live.reload.revoked?).to be true
      expect(flash[:notice]).to eq("session revoked")
    end

    it "cancels (no DB writes) when confirm is missing" do
      sign_in_as(user)
      a, _ = Session.create_for!(user: user, ip: "10.0.0.45", user_agent: "A")

      post settings_sessions_bulk_revoke_path(ids: a.id.to_s)

      expect(response).to redirect_to(settings_path)
      expect(flash[:alert]).to eq("revoke cancelled.")
      expect(a.reload.revoked?).to be false
    end

    it "silently ignores ids belonging to other users" do
      sign_in_as(user)
      other_user = create(:user)
      mine, _ = Session.create_for!(user: user, ip: "10.0.0.46", user_agent: "Mine")
      theirs, _ = Session.create_for!(user: other_user, ip: "10.0.0.47", user_agent: "Theirs")

      post settings_sessions_bulk_revoke_path(ids: [ mine.id, theirs.id ].join(",")), params: { confirm: "yes" }

      expect(mine.reload.revoked?).to be true
      expect(theirs.reload.revoked?).to be false
    end

    it "redirects to /settings with `nothing to revoke.` alert when the id list resolves to no rows" do
      sign_in_as(user)
      other_user = create(:user)
      not_mine, _ = Session.create_for!(user: other_user, ip: "10.0.0.48", user_agent: "Other")

      post settings_sessions_bulk_revoke_path(ids: not_mine.id.to_s), params: { confirm: "yes" }

      expect(response).to redirect_to(settings_path)
      expect(flash[:alert]).to eq("nothing to revoke.")
    end
  end

  # 2026-05-16 (sessions revamp v2). The standalone routes were
  # explicitly dropped from `config/routes.rb`. Defense-in-depth:
  # asking the router to recognize the dropped paths should miss.
  # 2026-05-16 (sessions revamp v3). The GET `/settings/sessions/revokes/:ids`
  # action-screen route was also dropped — only POST survives.
  describe "dropped standalone routes" do
    it "no longer recognizes GET /settings/sessions" do
      expect {
        Rails.application.routes.recognize_path("/settings/sessions", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end

    it "no longer recognizes DELETE /settings/sessions/:id" do
      expect {
        Rails.application.routes.recognize_path("/settings/sessions/1", method: :delete)
      }.to raise_error(ActionController::RoutingError)
    end

    it "no longer recognizes GET /settings/sessions/:id/revoke" do
      expect {
        Rails.application.routes.recognize_path("/settings/sessions/1/revoke", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end

    it "no longer recognizes GET /settings/sessions/revokes/:ids (action-screen page is gone — modal flow only)" do
      expect {
        Rails.application.routes.recognize_path("/settings/sessions/revokes/1,2", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end
  end
end
