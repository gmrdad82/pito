require "rails_helper"

# Phase 27 §01f — Per-platform ownership editor system spec (revamped
# 2026-05-12).
#
# Walks the user journey:
#   1. Visit /games/:slug.
#   2. Click [edit ownership] → land on /games/:slug/platform_ownerships/edit.
#   3. Tick a checkbox for one or more platforms (bracketed `[ ]` / `[x]`
#      via the `.md-check` pattern).
#   4. Click [save] → redirect back to /games/:slug.
#   5. Show page now lists the ticked platforms as chips.
#   6. Re-enter editor, un-tick, save → show page reflects the change.
#
# Capybara's rack_test driver is sufficient — there is no JS in this
# surface beyond standard form submission.
RSpec.describe "Games — per-platform ownership editor (01f)", type: :system do
  before { driven_by(:rack_test) }

  let!(:game)  { create(:game, :synced, title: "Zelda BotW", igdb_slug: "zelda") }
  let!(:ps5)   { create(:platform, name: "PS5",   slug: "ps5") }
  let!(:steam) { create(:platform, name: "Steam", slug: "steam") }

  before do
    game.platforms_available << ps5
    game.platforms_available << steam
  end

  describe "happy: tick a platform" do
    it "tick PS5 + Steam → show page reads both as chips" do
      visit game_path(game)
      click_link "edit ownership"

      expect(page).to have_current_path(edit_game_platform_ownerships_path(game))

      # Tick both checkboxes. Every absent platform on submit is
      # treated as not owned.
      page.all('input[type="checkbox"]', visible: :all).each(&:check)
      click_button "save"

      expect(page).to have_current_path(game_path(game))
      chips = find("span.owned-platforms-chip-list")
      expect(chips).to have_link("PS5")
      expect(chips).to have_link("Steam")
      expect(page).not_to have_content("(not owned on any platform)")
    end
  end

  describe "happy: un-tick a previously owned platform" do
    before do
      create(:game_platform_ownership, game: game, platform: ps5)
      create(:game_platform_ownership, game: game, platform: steam)
    end

    it "un-tick PS5 leaves Steam owned" do
      visit edit_game_platform_ownerships_path(game)

      ps5_row = find("label.md-check[data-platform-slug='ps5']")
      ps5_row.find('input[type="checkbox"]', visible: :all).uncheck

      click_button "save"

      expect(page).to have_current_path(game_path(game))
      chips = find("span.owned-platforms-chip-list")
      expect(chips).to have_link("Steam")
      expect(chips).not_to have_link("PS5")
    end
  end

  describe "happy: simplified editor surface" do
    it "renders only the 'ownership' heading and checkbox rows — no metadata inputs" do
      visit edit_game_platform_ownerships_path(game)

      expect(page).to have_css("h2", text: "ownership")
      expect(page).not_to have_content("per-platform")
      expect(page).not_to have_content("tick the platforms you own this game on")
      expect(page).not_to have_css('input[type="date"]')
      expect(page).not_to have_css("textarea")
      expect(page).not_to have_css("fieldset")
    end
  end

  describe "sad: no JS confirm" do
    it "the editor form does not use data-turbo-confirm" do
      visit edit_game_platform_ownerships_path(game)
      expect(page.html).not_to include("data-turbo-confirm")
    end

    it "the [edit ownership] link on the show page does not use confirm" do
      visit game_path(game)
      link = find_link("edit ownership")
      expect(link["data-turbo-confirm"]).to be_nil
    end
  end

  describe "edge: empty state on show page" do
    it "shows the muted '(not owned on any platform)' placeholder when no rows exist" do
      visit game_path(game)
      expect(page).to have_css("span.owned-platforms-chip-list--empty",
                               text: "(not owned on any platform)")
    end
  end

  describe "edge: composes with the filter row contract" do
    it "the chip href targets /games?filters=<slug>,owned" do
      create(:game_platform_ownership, game: game, platform: ps5)
      visit game_path(game)
      link = find_link("PS5")
      # URL-encoded comma may render as `%2C` depending on the helper.
      expect(link[:href]).to match(%r{/games\?filters=ps5(%2C|,)owned})
    end
  end
end
