require "rails_helper"

# 2026-05-18 (revision 2) — KeybindingsReferenceComponent renders the
# leader-popup card as TWO sections:
#
#   * "local"  — per-page action rows (formerly "page actions"). On
#                /games this includes l/{/} + filter chips + G+ add
#                game + Gb add bundle. Empty when the page is
#                deny-listed or the YAML has no entry AND no `default:`
#                fallback.
#   * "global" — the always-true navigation surface (formerly
#                "navigation"). Trimmed to /games + /settings + logout
#                only.
#
# Groups within each section are bounded by divider rows; a divider
# carrying `layout: grid_2col` opens a 2-column grid that closes at
# the next divider OR end-of-list. The grid renders inside
# `<div class="keybindings-grid keybindings-grid--two-col">` with an
# inline `grid-template-rows: repeat(<half>, auto)` so the
# `grid-auto-flow: column` CSS rule fills items column-first.
RSpec.describe KeybindingsReferenceComponent, type: :component do
  describe "#navigation_items (trimmed root menu)" do
    let(:items) { described_class.new.navigation_items }

    it "returns an Array of row hashes" do
      expect(items).to be_an(Array)
      expect(items).to all(be_a(Hash))
    end

    it "exposes the [Gl] games direct binding" do
      gl = items.find { |i| i["key"] == "Gl" }
      expect(gl).not_to be_nil
      expect(gl["label"]).to eq("games")
      expect(gl["action"]).to eq("type" => "navigate", "path" => "/games")
    end

    it "exposes the [S] settings direct binding" do
      settings = items.find { |i| i["key"] == "S" }
      expect(settings).not_to be_nil
      expect(settings["label"]).to eq("settings")
      expect(settings["action"]).to eq("type" => "navigate", "path" => "/settings")
    end

    it "exposes the [Q] logout direct binding" do
      logout = items.find { |i| i["key"] == "Q" }
      expect(logout).not_to be_nil
      expect(logout["label"]).to eq("logout")
      expect(logout["action"]).to eq("type" => "logout")
    end

    it "does not ship the [h] home binding (dropped 2026-05-18)" do
      expect(items.find { |i| i["key"] == "h" }).to be_nil
    end

    it "does not ship any calendar / channels / videos / projects / notifications binding (dropped 2026-05-18)" do
      keys = items.reject { |i| i["divider"] }.map { |i| i["key"] }
      dropped = %w[cs cm ct c+ Cl C+ C- Cy Vl V+ V- Pl P+ P- Nl Nu Nm]
      offenders = keys & dropped
      expect(offenders).to be_empty,
        "expected the dropped keys to be absent, found #{offenders.inspect}"
    end

    it "does not ship the [G+] root binding (moved to page_actions.games_index as 'add game')" do
      expect(items.find { |i| i["key"] == "G+" }).to be_nil
    end

    it "ships no row carrying a `submenu` field" do
      offenders = items.select { |i| i.key?("submenu") }
      expect(offenders).to be_empty,
        "expected no rows with `submenu`, found #{offenders.inspect}"
    end

    it "no two binding rows share the same key (collision guard)" do
      keys = items.reject { |i| i["divider"] }.map { |i| i["key"] }
      expect(keys.uniq.length).to eq(keys.length),
        "expected every binding key to be unique, got duplicates in #{keys.inspect}"
    end
  end

  describe "#local_groups (page_actions folded into groups)" do
    let(:groups) { described_class.new(page_key: "games_index").local_groups }

    it "produces three groups: header (l + /), filter-chips grid, create-row grid" do
      expect(groups.size).to eq(3)
    end

    it "first group is single-column header carrying l + /" do
      expect(groups.first.layout).to eq(:single)
      keys = groups.first.items.map { |i| i["key"] }
      expect(keys).to eq([ "l", "/" ])
    end

    it "second group is the 2-col filter-chips grid (fr/fs/fo/fw/fp + fP/fN/fS)" do
      expect(groups[1].layout).to eq(:grid_2col)
      keys = groups[1].items.map { |i| i["key"] }
      expect(keys).to eq(%w[fr fs fo fw fp fP fN fS])
    end

    it "third group is the 2-col create-row grid (G+ + Gb)" do
      expect(groups[2].layout).to eq(:grid_2col)
      keys = groups[2].items.map { |i| i["key"] }
      expect(keys).to eq(%w[G+ Gb])
    end
  end

  describe "render — section headings + 2-col grid markup" do
    it "renames sections to `local` + `global`" do
      render_inline(described_class.new(page_key: "games_index"))
      expect(page).to have_css("section[data-section='local'] h3", text: "local")
      expect(page).to have_css("section[data-section='global'] h3", text: "global")
    end

    it "does NOT render the legacy `page actions` / `navigation` headings" do
      render_inline(described_class.new(page_key: "games_index"))
      expect(page).not_to have_css("h3", text: "page actions")
      expect(page).not_to have_css("h3", text: "navigation")
    end

    it "emits the 2-col grid wrapper for the filter-chips group" do
      render_inline(described_class.new(page_key: "games_index"))
      grids = page.all(".keybindings-grid--two-col", visible: :all)
      expect(grids.size).to eq(2),
        "expected two 2-col grids (filter chips + create-row), got #{grids.size}"
    end

    # 2026-05-18 — vertical hairline between the two columns is
    # painted by `.keybindings-grid--two-col::before` (pseudo-element
    # in the column-gap, var(--color-border) tone). The CSS lives in
    # `app/assets/tailwind/application.css`. This spec guards the
    # structural anchor — the modifier class — so a future agent
    # removing it would break the hairline silently otherwise.
    it "every 2-col grid carries the `keybindings-grid--two-col` class the hairline pseudo-element hooks into" do
      render_inline(described_class.new(page_key: "games_index"))
      page.all(".keybindings-grid--two-col", visible: :all).each do |grid|
        expect(grid[:class]).to include("keybindings-grid--two-col")
      end
    end

    it "filter-chips grid carries grid-template-rows: repeat(4, auto) for 8 items" do
      render_inline(described_class.new(page_key: "games_index"))
      grid = page.all(".keybindings-grid--two-col")[0]
      # 8 items / 2 cols → ceil(8/2) = 4 rows per column.
      expect(grid[:style]).to include("grid-template-rows: repeat(4, auto)")
    end

    it "create-row grid carries grid-template-rows: repeat(1, auto) for 2 items" do
      render_inline(described_class.new(page_key: "games_index"))
      grid = page.all(".keybindings-grid--two-col")[1]
      expect(grid[:style]).to include("grid-template-rows: repeat(1, auto)")
    end

    it "renders the [G+] add game row inside the create-row grid" do
      render_inline(described_class.new(page_key: "games_index"))
      grid = page.all(".keybindings-grid--two-col")[1]
      expect(grid).to have_css("kbd", text: "G+")
      expect(grid).to have_css("span", text: "add game")
    end

    it "renders the [Gb] add bundle row inside the create-row grid" do
      render_inline(described_class.new(page_key: "games_index"))
      grid = page.all(".keybindings-grid--two-col")[1]
      expect(grid).to have_css("kbd", text: "Gb")
      expect(grid).to have_css("span", text: "add bundle")
    end

    it "renames the [l] row label to `dark mode toggle`" do
      render_inline(described_class.new(page_key: "games_index"))
      expect(page).to have_css(".keybindings-row span", text: "dark mode toggle")
    end

    it "renders the [Gl] games row in the global section" do
      render_inline(described_class.new(page_key: "games_index"))
      global = page.find("section[data-section='global']")
      expect(global).to have_css("kbd", text: "Gl")
      expect(global).to have_css("span", text: "games")
    end

    it "global section paints visible dividers between groups (Gl/S/q | Q)" do
      render_inline(described_class.new(page_key: "games_index"))
      global = page.find("section[data-section='global']")
      expect(global).to have_css("hr.keybindings-divider")
    end

    it "does not render a submenu arrow on any row (no `→ <submenu>` text)" do
      render_inline(described_class.new(page_key: "games_index"))
      expect(page.text).not_to include("→")
    end

    # 2026-05-18 — consolidation sweep. Asserts the full /games
    # leader-popup binding set is reachable in the RENDERED output
    # (not just the YAML / component method layer). Catches regressions
    # where a binding silently disappears from the popup card even
    # while the underlying schema still ships it.
    describe "rendered binding sweep — /games popup must render every in-scope key" do
      let(:rendered) { render_inline(described_class.new(page_key: "games_index")) }

      %w[l / fr fs fo fw fp fP fN fS G+ Gb].each do |key|
        it "renders the [#{key}] binding inside the local section" do
          rendered
          local = page.find("section[data-section='local']")
          expect(local).to have_css("kbd", text: Regexp.new("\\A#{Regexp.escape(key)}\\z"))
        end
      end

      %w[Gl S Q].each do |key|
        it "renders the [#{key}] binding inside the global section" do
          rendered
          global = page.find("section[data-section='global']")
          expect(global).to have_css("kbd", text: Regexp.new("\\A#{Regexp.escape(key)}\\z"))
        end
      end

      it "renders NO dropped key (h / cs / cm / ct / c+ / Cl / C+ / C- / Cy / Vl / V+ / V- / Pl / P+ / P- / Nl / Nu / Nm) in the rendered output" do
        rendered
        dropped = %w[h cs cm ct c+ Cl C+ C- Cy Vl V+ V- Pl P+ P- Nl Nu Nm]
        kbd_labels = page.all("kbd").map(&:text)
        offenders = kbd_labels & dropped
        expect(offenders).to be_empty,
          "expected no dropped keys in the rendered popup, found #{offenders.inspect}"
      end
    end
  end

  describe "render — empty local section short-circuits cleanly" do
    it "omits the local section when no page_key is supplied" do
      render_inline(described_class.new)
      expect(page).not_to have_css("section[data-section='local']")
      expect(page).to have_css("section[data-section='global']")
    end

    it "omits the local section for the deny-listed `admin` page" do
      render_inline(described_class.new(page_key: "admin"))
      expect(page).not_to have_css("section[data-section='local']")
    end
  end

  # 2026-05-18 — /settings popup mirrors /games structure: a single-
  # column `l` header, a single-column `sr` row, a 2-col grid block
  # holding the four notification toggles (da/dd | sa/sd), and a
  # single-column `vr` row at the bottom. Plain dividers separate
  # every block from its neighbour. The notification grid uses the
  # same `grid-auto-flow: column` + `grid-template-rows: repeat(2,
  # auto)` recipe as the /games filter-chips grid so column-first
  # auto-flow places col1 = [da, dd] and col2 = [sa, sd], matching
  # the user's mock 1-for-1.
  describe "#local_groups (settings page_actions folded into groups)" do
    let(:groups) { described_class.new(page_key: "settings").local_groups }

    it "produces four groups: header (l), sr, notifications 2-col grid, vr" do
      expect(groups.size).to eq(4)
    end

    it "first group is single-column header carrying just l (dark mode)" do
      expect(groups[0].layout).to eq(:single)
      keys = groups[0].items.map { |i| i["key"] }
      expect(keys).to eq([ "l" ])
    end

    it "second group is single-column carrying just sr (revoke unused sessions)" do
      expect(groups[1].layout).to eq(:single)
      keys = groups[1].items.map { |i| i["key"] }
      expect(keys).to eq([ "sr" ])
    end

    it "third group is the 2-col notifications grid (da/dd + sa/sd in YAML order)" do
      expect(groups[2].layout).to eq(:grid_2col)
      keys = groups[2].items.map { |i| i["key"] }
      expect(keys).to eq(%w[da dd sa sd])
    end

    it "fourth group is single-column carrying just vr (Voyage reindex)" do
      expect(groups[3].layout).to eq(:single)
      keys = groups[3].items.map { |i| i["key"] }
      expect(keys).to eq([ "vr" ])
    end
  end

  describe "render — /settings layout matches the /games structure" do
    it "renders the local + global sections" do
      render_inline(described_class.new(page_key: "settings"))
      expect(page).to have_css("section[data-section='local'] h3", text: "local")
      expect(page).to have_css("section[data-section='global'] h3", text: "global")
    end

    it "emits exactly one 2-col grid (the notifications block)" do
      render_inline(described_class.new(page_key: "settings"))
      grids = page.all(".keybindings-grid--two-col", visible: :all)
      expect(grids.size).to eq(1)
    end

    it "notifications grid carries grid-template-rows: repeat(2, auto) for 4 items" do
      render_inline(described_class.new(page_key: "settings"))
      grid = page.find(".keybindings-grid--two-col")
      # 4 items / 2 cols → ceil(4/2) = 2 rows per column.
      expect(grid[:style]).to include("grid-template-rows: repeat(2, auto)")
    end

    it "notifications grid contains da/dd/sa/sd rows in YAML order (column-first → col1=[da,dd], col2=[sa,sd])" do
      render_inline(described_class.new(page_key: "settings"))
      grid = page.find(".keybindings-grid--two-col")
      kbds = grid.all("kbd").map(&:text)
      expect(kbds).to eq(%w[da dd sa sd])
    end

    it "renders every notification toggle label inside the grid" do
      render_inline(described_class.new(page_key: "settings"))
      grid = page.find(".keybindings-grid--two-col")
      expect(grid).to have_css("span", text: "Discord all")
      expect(grid).to have_css("span", text: "Discord daily digest")
      expect(grid).to have_css("span", text: "Slack all")
      expect(grid).to have_css("span", text: "Slack daily digest")
    end

    it "renders the l (dark mode) row outside the grid" do
      render_inline(described_class.new(page_key: "settings"))
      local = page.find("section[data-section='local']")
      expect(local).to have_css(".keybindings-row kbd", text: "l")
      expect(local).to have_css(".keybindings-row span", text: "dark mode")
    end

    it "keeps the l label as `dark mode` (NOT `dark mode toggle` — that is /games-only)" do
      render_inline(described_class.new(page_key: "settings"))
      local = page.find("section[data-section='local']")
      expect(local).not_to have_css(".keybindings-row span", text: "dark mode toggle")
    end

    it "renders the sr (revoke unused sessions) row outside the grid" do
      render_inline(described_class.new(page_key: "settings"))
      local = page.find("section[data-section='local']")
      expect(local).to have_css(".keybindings-row kbd", text: "sr")
      expect(local).to have_css(".keybindings-row span", text: "revoke unused sessions")
    end

    it "renders the vr (Voyage reindex) row outside the grid" do
      render_inline(described_class.new(page_key: "settings"))
      local = page.find("section[data-section='local']")
      expect(local).to have_css(".keybindings-row kbd", text: "vr")
      expect(local).to have_css(".keybindings-row span", text: "Voyage reindex")
    end

    it "paints visible hairlines between the four local groups (3 dividers inside local)" do
      render_inline(described_class.new(page_key: "settings"))
      local = page.find("section[data-section='local']")
      expect(local).to have_css("hr.keybindings-divider", count: 3)
    end

    it "still renders the global section with [Gl] games + [S] settings + [Q] logout" do
      render_inline(described_class.new(page_key: "settings"))
      global = page.find("section[data-section='global']")
      expect(global).to have_css("kbd", text: "Gl")
      expect(global).to have_css("kbd", text: "S")
      expect(global).to have_css("kbd", text: "Q")
    end
  end

  describe "page_actions accessor (regression — flat-list compat surface)" do
    it "returns [] when initialized with no page_key" do
      expect(described_class.new.page_actions).to eq([])
    end

    it "returns [] for a deny-listed page key" do
      expect(described_class.new(page_key: "admin").page_actions).to eq([])
    end

    it "resolves the games_index page_actions when given that key" do
      rows = described_class.new(page_key: "games_index").page_actions
      keys = rows.reject { |r| r["divider"] }.map { |r| r["key"] }
      expect(keys).to include("l", "/", "fr", "fo", "fP", "G+", "Gb")
    end
  end
end
