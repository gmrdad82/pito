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

    # FB-174 (2026-05-21) — supersedes FB-134/FB-140.
    #
    # The select-all heading checkbox is now reachable via the
    # generic `data-tui-focusable` contract (style: :checkbox_label),
    # NOT the legacy `data-tui-cursor-target="row"` attribute (which
    # FB-146 already removed from the defaultHeader). The
    # `<th data-tui-focusable="select_all">` is the FIRST entry in
    # `Sessions::TableComponent#focusables` so `j` from a session
    # row 1 → no movement (clamped at 0), and `k` from row 1 → lands
    # on select_all. See the `#focusables` describe block below for
    # the full contract.
    # FB-PURPLE-REGRESSION (2026-05-21) — focusable moved from the
    # single select-all `<th>` to the parent `<tr>` so the focus tint
    # paints across the full header row (matches body-row behavior).
    # Style is now `:row` instead of `:checkbox_label`.
    it "stamps `data-tui-focusable=\"select_all\"` on the defaultHeader `<tr>`" do
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'][data-tui-focusable='select_all'][data-tui-focusable-style='row']",
        visible: :all
      )
    end

    it "does NOT mark the actionHeader's select-all `<th>` as a focusable (it disappears on revoke selection)" do
      expect(page).to have_no_css(
        "thead tr[data-sessions-bulk-revoke-target='actionHeader'] th[data-tui-focusable]",
        visible: :all
      )
    end

    it "exposes 4 `[data-tui-focusable]` targets total — select_all heading + 3 body rows" do
      # FB-174 — the focus ring grows from 3 (rows only) to 4
      # (select-all heading + 3 body rows), matching the Ruby
      # `#focusables` contract which prepends a `select_all` entry.
      expect(page).to have_css("[data-tui-focusable]", count: 4, visible: :all)
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

    # FB-131 (2026-05-21) — Bug B: `<colgroup>` + `table-layout: fixed`
    # lock column widths so the row swap (defaultHeader ↔ actionHeader)
    # no longer reflows on selection.
    it "renders a `<colgroup>` with 6 explicit-width `<col>` cells" do
      expect(page).to have_css("table.sessions-table colgroup col", count: 6, visible: :all)
    end

    it "stamps `table-layout: fixed` on the sessions table to prevent jiggle on selection" do
      expect(page).to have_css("table.sessions-table[style*='table-layout: fixed']", visible: :all)
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

    it "renders the TUI checkbox primitive on every row (3 rows + 2 headers = 5 total)" do
      # Each row's `<span class="sessions-table__checkbox">` wraps a
      # `Tui::CheckboxComponent` (form mode → `<label class=
      # "tui-checkbox">`). FB-131 (2026-05-21) — Bug A: the action
      # header ALSO carries a select-all checkbox so the column-1
      # affordance survives the row swap. Both headers wrap a
      # `--header` modifier; total in `<thead>` = 2.
      expect(page).to have_css("span.sessions-table__checkbox label.tui-checkbox", count: 5, visible: :all)
      expect(page).to have_css("tbody span.sessions-table__checkbox label.tui-checkbox", count: 3)
      expect(page).to have_css("thead span.sessions-table__checkbox--header label.tui-checkbox", count: 2, visible: :all)
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
      # FB-50 — `user_agent` column was split into device + browser;
      # check that an inactive column (device) points to asc on first
      # click instead.
      render_table(sort: "last_activity", dir: "desc")
      expect(page).to have_css(
        "a[href*='sessions_sort=device'][href*='sessions_dir=asc']"
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

  # FB-166 (2026-05-21) — Ruby-declared focusables contract. The
  # component's `#focusables` method returns the ordered list of
  # focusables for the j/k cursor; each entry carries a `:key` (stable
  # domain id) + `:style` (drives the CSS focus visual). The template
  # emits `data-tui-focusable` + `data-tui-focusable-style` from this
  # contract — specs lock the contract here so HTML drift is caught.
  #
  # FB-174 (2026-05-21) — the contract now prepends a `select_all`
  # focusable (style: :checkbox_label) so keyboard nav reaches the
  # heading's select-all checkbox as the FIRST stop. j/k cycles
  # select_all → row_0 → row_1 → ... → row_N (clamped at the ends).
  describe "#focusables (FB-166 + FB-174 — Ruby-driven focus contract)" do
    it "exposes select_all + all session rows as focusables, select_all first" do
      component = described_class.new(
        sessions: sessions,
        sessions_sort: "last_activity",
        sessions_dir: "desc",
        current_session_id: current_session.id
      )
      keys = component.focusables.map { |f| f[:key] }
      expect(keys).to eq([
        "select_all",
        "row_#{current_session.id}",
        "row_#{other_session_a.id}",
        "row_#{other_session_b.id}"
      ])
    end

    # FB-PURPLE-REGRESSION (2026-05-21) — style flipped to `:row` so the
    # header `<tr>` focus tint paints across the entire row (matches
    # body-row behavior). `:checkbox_label` only made sense when the
    # focusable hugged the single `<th>` checkbox cell.
    it "stamps select_all with style `:row`" do
      component = described_class.new(
        sessions: sessions,
        sessions_sort: "last_activity",
        sessions_dir: "desc",
        current_session_id: current_session.id
      )
      expect(component.focusables.first).to eq(key: "select_all", style: :row)
    end

    it "stamps every session row focusable with style `:row` (full-width tint)" do
      component = described_class.new(
        sessions: sessions,
        sessions_sort: "last_activity",
        sessions_dir: "desc",
        current_session_id: current_session.id
      )
      row_styles = component.focusables.drop(1).map { |f| f[:style] }
      expect(row_styles).to all(eq(:row))
    end

    it "returns just the select_all entry when there are no sessions" do
      # FB-174 — select_all is part of the focusables contract
      # regardless of session count; the heading's checkbox always
      # exists in the defaultHeader row. The empty-state branch in
      # the template skips both <thead> and <tbody>, but the Ruby
      # contract still returns select_all (specs lock the Ruby
      # contract — the template's empty-state is a separate concern).
      component = described_class.new(
        sessions: [],
        sessions_sort: "last_activity",
        sessions_dir: "desc",
        current_session_id: nil
      )
      expect(component.focusables).to eq([
        { key: "select_all", style: :row }
      ])
    end

    it "emits `data-tui-focusable-style=\"row\"` on each body row" do
      render_table
      expect(page).to have_css(
        "tbody tr.tui-table__row[data-tui-focusable^='row_'][data-tui-focusable-style='row']",
        count: 3
      )
    end

    # FB-PURPLE-REGRESSION (2026-05-21) — focusable moved from the
    # single select-all `<th>` to the parent `<tr>` so the focus tint
    # paints across the full header row. Style is now `:row` instead
    # of `:checkbox_label`.
    it "emits `data-tui-focusable=\"select_all\"` on the defaultHeader `<tr>`" do
      render_table
      expect(page).to have_css(
        "thead tr[data-sessions-bulk-revoke-target='defaultHeader'][data-tui-focusable='select_all'][data-tui-focusable-style='row']",
        visible: :all
      )
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

    it "renders two header checkbox target wrappers (FB-131) — one per header row" do
      # FB-131 (2026-05-21) — Bug A: defaultHeader + actionHeader BOTH
      # carry a column-1 select-all checkbox so the deselect-all
      # affordance survives the row swap. Stimulus auto-collects them
      # as `headerCheckboxTargets`.
      expect(page).to have_css(
        "span.sessions-table__checkbox--header[data-sessions-bulk-revoke-target='headerCheckbox']",
        count: 2,
        visible: :all
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
