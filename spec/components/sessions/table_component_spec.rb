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
#
# 2026-05-20 — Beta 4 Phase F3-C. Row + header checkboxes swapped to
# `Tui::CheckboxComponent` (form mode) per ADR 0016. The stimulus
# targets + `data-current` host element move to `<span class=
# "sessions-table__checkbox">` wrappers around each TUI component
# render. The current-session marker swaps from
# `StatusBadgeComponent label: "this", kind: :strong` to
# `Tui::ChipComponent label: "this", variant: :current`.
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

    it "renders the TUI checkbox primitive on every row (3 rows + 1 header = 4 total)" do
      # Each row's `<span class="sessions-table__checkbox">` wraps a
      # `Tui::CheckboxComponent` (form mode → `<label class=
      # "tui-checkbox">`). The header gets the same primitive inside
      # `--header` wrapper.
      expect(page).to have_css("span.sessions-table__checkbox label.tui-checkbox", count: 4)
      expect(page).to have_css("tbody span.sessions-table__checkbox label.tui-checkbox", count: 3)
    end
  end

  describe "current-session detection" do
    before { render_table }

    it "tags the matching row's checkbox wrapper with `data-current=\"yes\"`" do
      expect(page).to have_css(
        "span.sessions-table__checkbox[data-current='yes'][data-value='#{current_session.id}']",
        visible: :all
      )
    end

    it "stamps a `[this]` Tui chip with the :current variant on the matching row" do
      # The chip sits in the same cell as the user-agent code for the
      # current session — assert structurally, not by row position.
      expect(page).to have_css(
        "span.tui-chip.tui-chip--current", text: "this", count: 1
      )
    end

    it "tags every non-matching row's checkbox wrapper with `data-current=\"no\"`" do
      [ other_session_a, other_session_b ].each do |s|
        expect(page).to have_css(
          "span.sessions-table__checkbox[data-current='no'][data-value='#{s.id}']",
          visible: :all
        )
      end
    end

    it "renders the `[this]` chip exactly once even with multiple rows" do
      expect(page).to have_css("span.tui-chip--current", text: "this", count: 1)
    end

    it "does NOT render a `[this]` chip when no session matches current_session_id" do
      render_table(current_id: -1)
      expect(page).to have_no_css("span.tui-chip--current", text: "this")
    end

    it "does NOT render a `[this]` chip when current_session_id is nil" do
      render_table(current_id: nil)
      expect(page).to have_no_css("span.tui-chip--current", text: "this")
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

  describe "tabular-nums on the pinged column" do
    before { render_table }

    # `.num` carries `font-variant-numeric: tabular-nums` site-wide
    # (see `app/assets/tailwind/application.css` ~line 1086) — one
    # class drives both right-align + tabular digit alignment for the
    # "pinged" cells. Asserting on the class is enough.
    it "stamps the .num class on the pinged cell so digit widths align" do
      expect(page).to have_css("td.num", count: 3)
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

    it "renders the header checkbox target wrapper for select-all" do
      expect(page).to have_css(
        "span.sessions-table__checkbox--header[data-sessions-bulk-revoke-target='headerCheckbox']"
      )
    end

    it "renders a per-row checkbox target wrapper with the session id on data-value" do
      sessions.each do |s|
        expect(page).to have_css(
          "span.sessions-table__checkbox[data-sessions-bulk-revoke-target='checkbox'][data-value='#{s.id}']"
        )
      end
    end

    it "nests a real <input type=checkbox> inside each row's target wrapper" do
      sessions.each do |s|
        expect(page).to have_css(
          "span.sessions-table__checkbox[data-value='#{s.id}'] input[type='checkbox']",
          visible: :all
        )
      end
    end
  end
end
