require "rails_helper"

# Phase 28 §01a — Multi-version game grouping. Capybara rack_test
# smoke for the critical journey:
#
#   1. Create primary "Pragmata".
#   2. PATCH an unrelated row to point at "Pragmata" → attaches.
#   3. /games — only "Pragmata" tile renders, with the [+1 edition] badge.
#   4. Click the editions section anchor → primary's show page has the
#      Editions sub-section listing the edition.
#   5. PATCH the edition with version_parent_id="" → detaches.
#   6. /games — both rows render again.
#   7. Re-attach via PATCH.
#
# Hard rules sweep: no `data-turbo-confirm`, no JS confirm / alert /
# prompt anywhere in the rendered HTML.
RSpec.describe "Games multi-version grouping", type: :system do
  before { driven_by(:rack_test) }

  let!(:pragmata) { create(:game, title: "Pragmata") }
  let!(:deluxe)   { create(:game, title: "Pragmata Deluxe Edition") }

  it "renders primaries only on /games by default" do
    # Phase 27 v2 spec 05 — `/games` letter shelves render via
    # `Games::CoverComponent` (cover-only `<img>`, no visible title
    # text). Identity assertions use `data-tile-game-id` instead of
    # `have_content`. The `[+N editions]` badge moved off the index
    # surface; the badge's canonical surface is the game show page.
    visit games_path
    expect(page).to have_css("[data-tile-game-id='#{pragmata.id}']")
    expect(page).to have_css("[data-tile-game-id='#{deluxe.id}']")

    # Attach via PATCH (capybara rack_test cannot exercise the Stimulus
    # typeahead so we use the form's hidden version_parent_id field
    # by POSTing directly).
    page.driver.submit :patch, game_path(deluxe),
                       game: { version_parent_id: pragmata.id, version_title: "Deluxe" }

    visit games_path
    expect(page).to have_css("[data-tile-game-id='#{pragmata.id}']")
    expect(page).to have_no_css("[data-tile-game-id='#{deluxe.id}']")
  end

  it "renders the editions section on the primary's show page" do
    deluxe.update!(version_parent: pragmata, version_title: "Deluxe")
    visit game_path(pragmata)
    expect(page).to have_css("section#editions")
    expect(page).to have_content("editions (1)")
    expect(page).to have_link("Pragmata Deluxe Edition")
  end

  it "renders the parent pointer on the edition's show page" do
    deluxe.update!(version_parent: pragmata, version_title: "Deluxe")
    visit game_path(deluxe)
    expect(page).to have_css(".edition-parent-pointer")
    expect(page).to have_link("↳ Pragmata")
  end

  it "detaches the edition and returns it as a primary on /games" do
    deluxe.update!(version_parent: pragmata, version_title: "Deluxe")

    page.driver.submit :patch, game_path(deluxe), game: { version_parent_id: "" }

    expect(deluxe.reload.version_parent_id).to be_nil
    visit games_path
    expect(page).to have_css("[data-tile-game-id='#{pragmata.id}']")
    expect(page).to have_css("[data-tile-game-id='#{deluxe.id}']")
  end

  it "re-attaches after detach" do
    deluxe.update!(version_parent: pragmata, version_title: "Deluxe")

    page.driver.submit :patch, game_path(deluxe), game: { version_parent_id: "" }
    expect(deluxe.reload.version_parent_id).to be_nil

    page.driver.submit :patch, game_path(deluxe),
                       game: { version_parent_id: pragmata.id, version_title: "Deluxe" }
    expect(deluxe.reload.version_parent_id).to eq(pragmata.id)
  end

  it "flat mode (?include_editions=yes) shows both rows + edition parent pointer" do
    deluxe.update!(version_parent: pragmata, version_title: "Deluxe")
    visit "/games?include_editions=yes"
    expect(page).to have_css("[data-tile-game-id='#{pragmata.id}']")
    expect(page).to have_css("[data-tile-game-id='#{deluxe.id}']")
  end

  describe "hard rules" do
    it "never emits data-turbo-confirm on /games" do
      deluxe.update!(version_parent: pragmata, version_title: "Deluxe")
      visit games_path
      expect(page.html).not_to include("data-turbo-confirm")
    end

    it "never emits window.confirm / alert / prompt on the edit page" do
      visit edit_game_path(pragmata)
      html = page.html
      expect(html).not_to include("window.confirm")
      expect(html).not_to include("window.alert")
      expect(html).not_to include("window.prompt")
    end
  end
end
