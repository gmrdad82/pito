require "rails_helper"

# Help modal opened by `?` (and the visible `[_]` link in the
# footer chrome).
#
# Scope contract: page-level + global hotkeys ONLY. Navigation
# between pages and bulk operations are leader-driven (SPACE opens
# the leader menu — see `config/keybindings.yml` +
# `leader_menu_controller.js`); this modal documents the page-level
# bindings and tells the reader to press SPACE for everything else.
#
# 2026-05-10 refresh: the legacy `g d/g c/g v/g s/g e` navigation rows
# were dropped (now leader-driven); `space` (toggle row selection)
# was retired in favour of `x` (matches the TUI's row-selection key
# after SPACE was promoted to the leader in both surfaces).
RSpec.describe KeyboardShortcutsModalComponent, type: :component do
  it "renders a <dialog> element wired to the keyboard controller" do
    render_inline(described_class.new)
    expect(page).to have_css("dialog[data-keyboard-target='dialog'].pane-dialog")
    expect(page).to have_css("dialog[data-action*='click->keyboard#clickOutside']")
  end

  it "renders a [close] bracketed link wired to keyboard#close" do
    render_inline(described_class.new)
    expect(page).to have_css('a.bracketed[data-action="click->keyboard#close"]', text: "close")
  end

  it "opens with a leader-menu hint sentence pointing to SPACE" do
    render_inline(described_class.new)
    expect(page).to have_css(
      "p.keyboard-shortcuts-leader-hint",
      text: "Press SPACE for the leader menu (navigation between pages and bulk operations)."
    )
  end

  describe "section coverage" do
    before { render_inline(described_class.new) }

    it "renders the general section with `?`, `q`, `t`, `/`, `i`, and `Esc`" do
      section = page.find(".keyboard-shortcuts-section", text: /general/i)
      expect(section).to have_css("span.keycap", text: "?")
      expect(section).to have_css("span.keycap", text: "q")
      expect(section).to have_css("span.keycap", text: "t")
      expect(section).to have_css("span.keycap", text: "/")
      expect(section).to have_css("span.keycap", text: "i")
      expect(section).to have_css("span.keycap", text: "Esc")
      expect(section).to have_text("toggle this help")
      expect(section).to have_text("toggle dark/light theme")
      expect(section).to have_text("open search modal")
      expect(section).to have_text("open igdb add-game modal")
    end

    it "clarifies that `q` (back/close) maps to Esc on the web surface" do
      # The TUI uses `q` to back out; the web layer routes the same
      # intent through Esc. The modal copy notes the equivalence so
      # readers don't expect a `q` keybinding in the browser.
      section = page.find(".keyboard-shortcuts-section", text: /general/i)
      expect(section).to have_text(/back\s*\/\s*close\s*\(Esc on web\)/i)
    end

    it "renders the list-pages section with j / k / h / l / x / s / D / Y and f-prefix" do
      section = page.find(".keyboard-shortcuts-section", text: /list pages/i)
      %w[j k h l x s D Y f].each do |k|
        expect(section).to have_css("span.keycap", text: k)
      end
      expect(section).to have_text("toggle row selection")
      expect(section).to have_text(/starred/i)
      # 2026-05-10 hjkl ubiquity — `h / l` on list pages navigates the
      # paginator (`<a rel='prev'>` / `<a rel='next'>`); the help row
      # documents that even though no shipping surface paginates yet.
      expect(section).to have_text(/previous\s*\/\s*next page/i)
      # `space` is now the leader key — the help modal must not
      # describe it as row-level any more.
      expect(section).not_to have_css("span.keycap", text: "space")
      expect(section).not_to have_text(/connected/i)
      expect(section).not_to have_text(/bulk mode only/i)
      expect(section).not_to have_text(/toggle bulk mode/i)
      expect(section).to have_no_css("span.keycap", text: /^b$/)
    end

    # 2026-05-10 hjkl ubiquity — detail pages now bind `h / l` to
    # previous / next sibling record. The help modal documents the
    # new keys alongside the existing `v / s / Y / D` set.
    it "renders the detail-pages section with h / l / v / s / Y / D" do
      section = page.find(".keyboard-shortcuts-section", text: /detail pages/i)
      %w[h l v s Y D].each do |k|
        expect(section).to have_css("span.keycap", text: k)
      end
      expect(section).to have_text("view URL in browser")
      expect(section).to have_text(/previous\s*\/\s*next sibling/i)
    end

    # The list-pages section above documents `j / k` for rows. Tile
    # grids (`/games`, `/bundles`) reuse the same vertical keys but add
    # `h / l` for within-row movement. The help modal documents both
    # axes under a dedicated heading so readers know `h / l` is grid-
    # only (it is never bound on list pages).
    it "renders the tile-grids section with j / k and h / l" do
      section = page.find(".keyboard-shortcuts-section", text: /tile grids/i)
      %w[j k h l].each do |k|
        expect(section).to have_css("span.keycap", text: k)
      end
      expect(section).to have_text(/next\s*\/\s*previous row of tiles/i)
      expect(section).to have_text(/within row/i)
    end

    # Calendar month uses a different motion model — `j / k` jump a
    # full week (same weekday) instead of stepping a single visual row.
    # `h / l` step a day. The dedicated section calls this out so
    # readers don't expect the tile-grid semantics.
    it "renders the calendar-month section with week + day motion" do
      section = page.find(".keyboard-shortcuts-section", text: /calendar month/i)
      %w[j k h l].each do |k|
        expect(section).to have_css("span.keycap", text: k)
      end
      expect(section).to have_text(/jump a week/i)
      expect(section).to have_text(/step a day/i)
    end

    it "renders the confirmation-prompts section with `y` and Esc" do
      section = page.find(".keyboard-shortcuts-section", text: /confirmation/i)
      expect(section).to have_css("span.keycap", text: "y")
      expect(section).to have_css("span.keycap", text: "Esc")
      expect(section).to have_text("confirm")
      expect(section).to have_text("cancel")
    end
  end

  describe "retired bindings" do
    before { render_inline(described_class.new) }

    it "does not render the legacy `navigation` section" do
      # The `g d/g c/g v/g s/g e` rows lived under a `navigation`
      # heading. Both heading and rows are gone — navigation is
      # leader-driven now.
      expect(page).to have_no_css(".keyboard-shortcuts-section", text: /^navigation$/i)
    end

    it "does not advertise any g-prefix navigation binding" do
      [ "g d", "g c", "g v", "g s", "g e" ].each do |combo|
        expect(page).to have_no_text(combo)
      end
      [
        "go to dashboard",
        "go to channels",
        "go to videos",
        "go to saved views",
        "go to settings"
      ].each do |label|
        expect(page).to have_no_text(label)
      end
    end

    it "does not describe SPACE as toggle row selection" do
      # SPACE is the leader key now. The only mention of SPACE in
      # this modal is the leader-menu hint at the top — never as a
      # row-level binding.
      expect(page).to have_no_text(/space\b.*toggle row selection/i)
    end

    it "does NOT advertise the retired `f y` filter (mirrors CLI parity sweep)" do
      # `f y` (filter: syncing) was dropped after Path A2; the CLI's
      # help overlay was scrubbed of it in the same pass and Rails
      # follows.
      expect(page).to have_no_text(/filter:\s*syncing/i)
      expect(page).to have_no_text("f y")
    end
  end

  it "does not introduce a JS confirm / alert / prompt anywhere" do
    render_inline(described_class.new)
    rendered = page.native.to_html
    expect(rendered).not_to include("data-turbo-confirm")
    expect(rendered).not_to include("window.confirm")
    expect(rendered).not_to include("alert(")
    expect(rendered).not_to include("prompt(")
  end
end
