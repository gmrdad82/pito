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

    # 2026-05-20 — Beta 4 Phase F3-C. The table swapped from the local
    # `.sessions-table` styling to the canonical `.tui-table` grammar
    # so it picks up the TUI design-system primitives (hairline rows,
    # 13px monospace cells, header decoration). The `.sessions-table`
    # class is kept alongside `.tui-table` for the bulk-revoke wiring
    # (header + per-row checkbox wrappers still hook off the local
    # `.sessions-table__checkbox` modifier).
    it "renders the canonical `.tui-table` class on the <table>" do
      expect(page).to have_css("table.tui-table.sessions-table")
    end

    it "renders each row with the `.tui-table__row` modifier" do
      expect(page).to have_css("tbody tr.tui-table__row", count: 3)
    end

    it "renders each cell with the `.tui-table__td` modifier" do
      # FB-50 sessions rework — columns are now: checkbox + device +
      # browser + ip + last seen + created = 6 cells per row.
      # Three rows × six cells = 18 `.tui-table__td` elements total.
      expect(page).to have_css("tbody td.tui-table__td", count: 18)
    end

    it "renders per-column `<th>` cells in the default header (FB-116)" do
      # FB-116 — header split into two `<tr>` siblings:
      #   defaultHeader: 6 `<th>` cells (checkbox + 5 column labels)
      #   actionHeader:  2 `<th>` cells (checkbox + colspan="5" bar)
      # Total `<th>` in `<thead>` = 8. The defaultHeader's per-column
      # cells restore alignment over body columns (FB-108 contract).
      expect(page).to have_css("thead th.tui-table__th", count: 8, visible: :all)
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'] th.tui-table__th",
        count: 6,
        visible: :all
      )
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='actionHeader'] th.tui-table__th",
        count: 2,
        visible: :all
      )
    end

    it "stamps FB-108 alignment classes on the per-column header cells" do
      # Text columns (device / browser / ip) get `--left`; date
      # columns (last seen / created) get `--right` + `.num`
      # (tabular-nums via `.num` matches the body `<td>` cells).
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'] th.tui-table__th--left",
        text: "device"
      )
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'] th.tui-table__th--left",
        text: "browser"
      )
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'] th.tui-table__th--left",
        text: "ip"
      )
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'] th.tui-table__th--right.num",
        text: "last seen"
      )
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'] th.tui-table__th--right.num",
        text: "created"
      )
    end

    it "hides the action header row by default (no rows selected at SSR)" do
      # The Stimulus controller toggles `hidden` on selection change;
      # at first render no row is checked, so the action header is
      # the inactive one. Asserts on the attribute, not visibility,
      # because Capybara's :hidden filter is unstable inside <table>.
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='actionHeader'][hidden]",
        visible: :all
      )
      expect(page).to have_no_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'][hidden]",
        visible: :all
      )
    end

    it "does NOT render any zebra-striping classes (TUI hairline-only rule)" do
      # The TUI table family uses hairline borders only, no
      # alternating-row backgrounds — assert no `.tui-table--zebra` or
      # similar variant leaks through.
      expect(page).not_to have_css("table.tui-table--zebra")
      expect(page).not_to have_css("tr.tui-table__row--alt")
    end

    # FB-50 — the user-agent `<code>` cell was replaced with parsed
    # browser family (lowercase, no version) extracted by the
    # component. Firefox/Chrome/Safari are the three families
    # detectable from the stub UA strings above.
    it "renders the parsed browser family for each row" do
      expect(page).to have_content("firefox")
      expect(page).to have_content("chrome")
      expect(page).to have_content("safari")
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
    it "stamps the .num class on the time-cell columns so digit widths align" do
      # FB-50 — two time columns now carry `.num` (last seen +
      # created). Three rows × two cells = 6 `.num` cells.
      expect(page).to have_css("td.num", count: 6)
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
      # FB-50 — the [revoke] link is hidden at SSR (no rows selected
      # yet); the Stimulus controller reveals it on first checkbox
      # click. Match `visible: :all` so the assertion ignores the
      # default-hidden state.
      expect(page).to have_css(
        "a[data-sessions-bulk-revoke-target='link']",
        text: "[revoke]",
        visible: :all
      )
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
