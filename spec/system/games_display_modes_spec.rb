require "rails_helper"

# Phase 27 §01d — Display mode switcher + three modes on `/games`.
#
# Three first-class views: grid (default), list (alpha-grouped sticky
# letter headings), shelves-by-letter (one horizontal shelf per
# non-empty first letter). Clicking the switcher PATCHes
# `/users/games_preferences`, which persists the choice and redirects
# back to `/games?display=<mode>` so the resolved mode shows
# immediately. URL `?display=` overrides the persisted preference for
# a single request without writing.
#
# Capybara's rack_test driver is sufficient — the switcher is pure
# `button_to` forms (no JS) and the modes themselves are server-side
# branches. Sticky letter headings are CSS-only (declaration is
# inlined on the list partial and asserted via the per-partial view
# spec; this system spec covers integration only).
RSpec.describe "Games display modes (01d)", type: :system do
  before { driven_by(:rack_test) }

  let(:user) { @auto_signed_in_user }

  before do
    # At least one game per first-letter bucket so list mode renders
    # multiple letter-head rows and shelves-by-letter renders multiple
    # shelves. Cover image ids are stable to keep the snapshot
    # deterministic across runs.
    create(:game, :synced, title: "Apex Legends",
           igdb_id: 5_900_001, igdb_slug: "apex-display-system",
           cover_image_id: "img-apex")
    create(:game, :synced, title: "Borderlands",
           igdb_id: 5_900_002, igdb_slug: "borderlands-display-system",
           cover_image_id: "img-borderlands")
  end

  describe "default mode for a fresh user" do
    it "lands on grid mode" do
      visit games_path

      # The all-games section carries `data-display-mode="grid"`.
      expect(page).to have_css('section[data-display-mode="grid"]')
      expect(page).not_to have_css('section[data-display-mode="list"]')
      expect(page).not_to have_css('section[data-display-mode="shelves_by_letter"]')
    end

    it "renders the switcher with grid marked active" do
      visit games_path

      switcher = find(".display-mode-switcher")
      # Active mode = grid → the grid button carries the `active` class.
      expect(switcher).to have_css("button.bracketed.active", text: "grid")
      expect(switcher).not_to have_css("button.bracketed.active", text: "list")
      expect(switcher).not_to have_css("button.bracketed.active", text: "shelves")
    end
  end

  describe "switching modes via the switcher (persistence)" do
    it "clicking [list] persists the preference and renders list mode" do
      visit games_path

      within(".display-mode-switcher") do
        # Bracketed-link convention wraps the label in `.bl`; the
        # button's visible text is `[ list ]` with the inner span as
        # `list`. Match on the text.
        find("button.bracketed", text: "list").click
      end

      expect(user.reload.preferred_games_display_mode).to eq("list")
      expect(page).to have_css('section[data-display-mode="list"]')
      expect(page).to have_css("table.list-table")
    end

    it "clicking [shelves] persists and renders shelves-by-letter mode" do
      visit games_path

      within(".display-mode-switcher") do
        find("button.bracketed", text: "shelves").click
      end

      expect(user.reload.preferred_games_display_mode).to eq("shelves_by_letter")
      expect(page).to have_css('section[data-display-mode="shelves_by_letter"]')
    end

    it "the persisted preference survives a reload" do
      visit games_path
      within(".display-mode-switcher") do
        find("button.bracketed", text: "list").click
      end

      # Fresh visit (no `?display=` param) — persisted preference wins.
      visit games_path
      expect(page).to have_css('section[data-display-mode="list"]')
    end

    it "clicking [grid] restores grid mode from a non-default preference" do
      user.update!(preferred_games_display_mode: :list)
      visit games_path
      expect(page).to have_css('section[data-display-mode="list"]')

      within(".display-mode-switcher") do
        find("button.bracketed", text: "grid").click
      end

      expect(user.reload.preferred_games_display_mode).to eq("grid")
      expect(page).to have_css('section[data-display-mode="grid"]')
    end
  end

  describe "URL ?display= override" do
    it "overrides the persisted preference for a single request without writing" do
      user.update!(preferred_games_display_mode: :grid)
      visit games_path(display: "list")

      # The render reflects list mode.
      expect(page).to have_css('section[data-display-mode="list"]')
      # But the persisted preference is unchanged — `?display=` is
      # request-scoped.
      expect(user.reload.preferred_games_display_mode).to eq("grid")
    end

    it "accepts the `shelves` URL alias for `shelves_by_letter`" do
      visit games_path(display: "shelves")
      expect(page).to have_css('section[data-display-mode="shelves_by_letter"]')
    end
  end

  describe "shelves-by-letter mode" do
    it "renders one shelf per non-empty first letter and hides empty letters" do
      visit games_path(display: "shelves")

      # Apex → A, Borderlands → B. Z is absent.
      shelves_section = find('section[data-display-mode="shelves_by_letter"]')
      letters = shelves_section.all("h2").map(&:text)
      expect(letters).to include("A", "B")
      expect(letters).not_to include("Z")
    end
  end

  describe "list mode" do
    it "renders a table with letter-head rows interleaved between buckets" do
      visit games_path(display: "list")

      list_section = find('section[data-display-mode="list"]')
      expect(list_section).to have_css("tr.letter-head[data-letter='A']")
      expect(list_section).to have_css("tr.letter-head[data-letter='B']")
      # Each title links to /games/:slug.
      expect(list_section).to have_link("Apex Legends")
      expect(list_section).to have_link("Borderlands")
    end
  end

  describe "composition with the filter row" do
    it "preserves `?display=` across the filter row's clear-all link" do
      # Pin at least one ownership row so `?filters=owned` keeps a
      # game in the all-games partition (otherwise the index falls
      # into the "no games yet" branch which skips the mode partial).
      platform = create(:platform, name: "ps5", slug: "ps5")
      apex = Game.find_by(title: "Apex Legends")
      apex.game_platform_ownerships.create!(platform: platform)

      visit games_path(filters: "owned", display: "list")

      expect(page).to have_css('section[data-display-mode="list"]')
      # The filter row's [clear all] preserves the display override.
      expect(page).to have_link("clear all", href: /display=list/)
    end
  end

  describe "design-rule guards (CLAUDE.md hard rules)" do
    it "does NOT use any JS confirm / alert / data-turbo-confirm" do
      visit games_path
      switcher_html = find(".display-mode-switcher")["outerHTML"] || page.body
      expect(switcher_html).not_to include("data-turbo-confirm")
      expect(switcher_html).not_to include("window.confirm")
      expect(switcher_html).not_to include("alert(")
    end

    it "renders the switcher as `button_to` forms (no anchor tags)" do
      visit games_path
      # Three forms — one per mode. The switcher container holds them all.
      forms_in_switcher = find(".display-mode-switcher").all("form")
      expect(forms_in_switcher.length).to eq(3)
    end
  end
end
