require "rails_helper"

# 2026-05-18 — Beta-3 lane B candidate B7.
#
# Sessions::TableComponent owns the sortable sessions table inside the
# Security pane on `/settings`. Extracted from `_security_pane.html.erb`
# (lines 39-105). The page-level `<dialog id="revoke_sessions_modal">`
# confirm modal is a separate concern (B8) and is NOT part of this
# component's surface. The `data-controller="sessions-bulk-revoke"`
# Stimulus mount lives on the parent `<fieldset>`, not on this
# component.
RSpec.describe Sessions::TableComponent, type: :component do
  let(:user) { build_stubbed(:user) }
  let(:current_session) do
    build_stubbed(:session, user: user, user_agent: "Firefox/current",
                  ip: "10.0.0.1", last_activity_at: 30.seconds.ago)
  end
  let(:other_session_a) do
    build_stubbed(:session, user: user, user_agent: "Chrome/other-a",
                  ip: "10.0.0.2", last_activity_at: 2.minutes.ago)
  end
  let(:other_session_b) do
    build_stubbed(:session, user: user, user_agent: "Safari/other-b",
                  ip: "10.0.0.3", last_activity_at: 5.minutes.ago)
  end
  let(:sessions) { [ current_session, other_session_a, other_session_b ] }

  # `sort_link_to` calls `request.query_parameters.merge(...)` and
  # `link_to(..., url_hash)` which needs a known route — `/settings` is
  # the canonical mount for this table. `with_request_url` gives the
  # virtual request a real path so url_for resolves.
  def render_table(sessions_arg = sessions, sort: "last_activity", dir: "desc",
                    current_id: current_session.id)
    with_request_url("/settings") do
      render_inline(described_class.new(
        sessions: sessions_arg,
        sessions_sort: sort,
        sessions_dir: dir,
        current_session_id: current_id
      ))
    end
  end

  describe "row rendering" do
    before { render_table }

    it "renders one <tr> in the <tbody> per session" do
      expect(page).to have_css("table.sessions-table tbody tr", count: 3)
    end

    it "renders the user-agent in a <code> cell for each row" do
      expect(page).to have_css("code", text: "Firefox/current")
      expect(page).to have_css("code", text: "Chrome/other-a")
      expect(page).to have_css("code", text: "Safari/other-b")
    end
  end

  describe "current-session detection" do
    before { render_table }

    it "tags the matching row's checkbox with `data-current=\"yes\"`" do
      expect(page).to have_css(
        "input[type='checkbox'][value='#{current_session.id}'][data-current='yes']",
        visible: :all
      )
    end

    it "stamps a `[this]` strong status badge on the matching row" do
      # The badge sits in the same cell as the user-agent code for the
      # current session — assert structurally, not by row position.
      expect(page).to have_css(
        "span.status-badge.status-badge--strong", text: "this", count: 1
      )
    end

    it "tags every non-matching row's checkbox with `data-current=\"no\"`" do
      [ other_session_a, other_session_b ].each do |s|
        expect(page).to have_css(
          "input[type='checkbox'][value='#{s.id}'][data-current='no']",
          visible: :all
        )
      end
    end

    it "renders the `[this]` badge exactly once even with multiple rows" do
      expect(page).to have_css("span.status-badge--strong", text: "this", count: 1)
    end

    it "does NOT render a `[this]` badge when no session matches current_session_id" do
      render_table(current_id: -1)
      expect(page).to have_no_css("span.status-badge--strong", text: "this")
    end

    it "does NOT render a `[this]` badge when current_session_id is nil" do
      render_table(current_id: nil)
      expect(page).to have_no_css("span.status-badge--strong", text: "this")
    end
  end

  describe "sort links" do
    it "renders the active sort header with `dir` flipped to the opposite direction" do
      render_table(sort: "last_activity", dir: "desc")
      # active column flips desc->asc on next click
      expect(page).to have_css(
        "a[href*='sessions_sort=last_activity'][href*='sessions_dir=asc']"
      )
    end

    it "renders the inactive sort header pointing to its first-click direction (asc)" do
      render_table(sort: "last_activity", dir: "desc")
      expect(page).to have_css(
        "a[href*='sessions_sort=user_agent'][href*='sessions_dir=asc']"
      )
    end
  end

  describe "empty state" do
    before { render_table([]) }

    it "renders the `no active sessions.` copy" do
      expect(page).to have_content("no active sessions.")
    end

    it "does NOT render a sessions table" do
      expect(page).to have_no_css("table.sessions-table")
    end

    it "does NOT render the bulk-revoke toolbar link" do
      expect(page).to have_no_css("[data-sessions-bulk-revoke-target='link']")
    end
  end

  describe "bulk-revoke wiring (the table half — the modal is B8's surface)" do
    before { render_table }

    it "renders the bulk-revoke toolbar link target" do
      expect(page).to have_css("a[data-sessions-bulk-revoke-target='link']", text: "[revoke]")
    end

    it "renders the header checkbox target for select-all" do
      expect(page).to have_css(
        "input[type='checkbox'][data-sessions-bulk-revoke-target='headerCheckbox']",
        visible: :all
      )
    end

    it "renders a per-row checkbox target with the session id as value" do
      sessions.each do |s|
        expect(page).to have_css(
          "input[type='checkbox'][data-sessions-bulk-revoke-target='checkbox'][value='#{s.id}']",
          visible: :all
        )
      end
    end
  end
end
