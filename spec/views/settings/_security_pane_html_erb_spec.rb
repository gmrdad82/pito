require "rails_helper"

# Phase 29 (settings refactor) — security pane partial (row 1 right).
# Phase 32 follow-up (2026-05-16) — `[ 2FA / TOTP ]` launcher dropped.
# 2026-05-16 (sessions revamp v2) — the helper copy block, the
# `[ sessions ]` modal launcher, and the modal-trigger Stimulus
# wiring are gone. The sessions table renders INLINE inside the pane.
# 2026-05-16 (sessions revamp v3) — the revoke confirmation flow
# is now an in-page `<dialog>` modal mounted at the bottom of this
# pane (replacing the standalone `/settings/sessions/revokes/:ids`
# action-screen page). The view-spec coverage below asserts on the
# modal's structural mount; dynamic content (title count / warning
# visibility / form action with real ids) is populated client-side
# by the `sessions-bulk-revoke` Stimulus controller and exercised
# by JS-aware tests.
RSpec.describe "settings/_security_pane.html.erb", type: :view do
  let(:user) { FactoryBot.create(:user, :totp_enabled) }

  def assign_defaults(sessions: [])
    assign(:twofa_enabled, false)
    assign(:active_sessions_count, sessions.size)
    assign(:sessions, sessions)
    assign(:sessions_sort, "last_activity")
    assign(:sessions_dir, "desc")
    allow(Current).to receive(:user).and_return(user)
  end

  describe "structural chrome" do
    before do
      assign_defaults(sessions: [])
      render partial: "settings/security_pane"
    end

    it "renders the security heading" do
      expect(rendered).to include('<span class="pito-pane__title">security</span>')
    end

    it "renders the empty-state when the user has no active sessions" do
      expect(rendered).to include("no active sessions.")
    end

    it "does NOT render the revoke-sessions modal when there are no sessions" do
      # Modal is only mounted when at least one row exists — there is
      # nothing to revoke from the empty state.
      expect(rendered).not_to include('id="revoke_sessions_modal"')
    end
  end

  describe "dropped surfaces" do
    before do
      assign_defaults(sessions: [])
      render partial: "settings/security_pane"
    end

    # The helper copy block was: `2FA: on / active sessions: N` plus
    # `active sessions open in a modal.` / `the direct link still
    # works for JS-off clients.`. Every line is gone.
    it "no longer renders the 2FA / active-sessions counter copy" do
      expect(rendered).not_to match(/2FA:\s*<strong>/)
      expect(rendered).not_to include("active sessions:")
    end

    it "no longer renders the modal-vs-direct prose" do
      expect(rendered).not_to include("active sessions open in a modal")
      expect(rendered).not_to include("the direct link still works for JS-off clients")
    end

    it "no longer renders the `[ sessions ]` modal launcher" do
      # The bracketed-link label and the modal-trigger Stimulus action
      # are both gone. The pane no longer wires anything to
      # `settings-modal#open`.
      expect(rendered).not_to include('href="/settings/sessions"')
      expect(rendered).not_to include("click-&gt;settings-modal#open")
      expect(rendered).not_to include("click->settings-modal#open")
    end

    it "no longer renders a [ 2FA / TOTP ] launcher" do
      expect(rendered).not_to include("2FA / TOTP")
      expect(rendered).not_to include('href="/settings/security/totp"')
    end

    it "no longer renders a [ locations ] launcher" do
      expect(rendered).not_to include('href="/settings/security/blocks"')
    end
  end

  # Rich render assertions (with rows / sortable headers / bulk-revoke
  # controller wiring / inline-code IP styling) live in the
  # `/settings` request spec (`spec/requests/settings_spec.rb`) so the
  # render runs inside a real controller context with route helpers
  # bound to the settings dashboard. The view-spec wrapper here
  # (`SettingsController`-less, no route context) cannot resolve
  # `sort_link_to`'s `url_for`-style `link_to(hash, ...)` call.
end
