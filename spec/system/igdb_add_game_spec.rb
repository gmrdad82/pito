require "rails_helper"
require "ostruct"

# Phase 27 spec 04 (2026-05-17) — IGDB add-game modal polish.
#
# Capybara's rack_test driver covers the server-rendered surface:
#   - the global modal renders on `/games` (and every layout) with
#     trimmed copy, no `[search]` button, and a bracketed-muted
#     `[cancel]` link;
#   - clicking `[add]` on a stubbed IGDB result row redirects to the
#     new game's show page with the IGDB-canonical title visible in
#     the breadcrumb (not the `"Untitled game"` model default);
#   - the async `GameIgdbSync` job is enqueued on add;
#   - the `i` keypress wiring + 5-char auto-search behavior is JS-
#     driven and out of rack_test's reach — those behaviors are
#     exercised by the controller's pure-server pieces (the modal
#     markup is asserted in the view spec) and validated manually per
#     the spec's manual recipe.
RSpec.describe "IGDB add-game flow", type: :system do
  before { driven_by(:rack_test) }

  # IGDB API stubs — keeps the search endpoint deterministic.
  let(:search_payload) do
    [
      { "id" => 7346, "name" => "Pragmata", "slug" => "pragmata",
        "first_release_date" => 1_700_000_000 }
    ]
  end

  before do
    GameIgdbSync.clear
    allow(Rails.application.credentials).to receive(:igdb).and_return(
      OpenStruct.new(client_id: "id", client_secret: "secret")
    )
    stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
      .to_return(status: 200, body: { access_token: "T", expires_in: 5_184_000 }.to_json)
    stub_request(:post, "https://api.igdb.com/v4/games")
      .to_return(status: 200, body: search_payload.to_json)
  end

  describe "modal markup on /games" do
    it "renders the trimmed dialog title and input placeholder" do
      # 2026-05-18 polish — the literal "add a game" copy was removed
      # too (per the modal's own header comment: "the modal itself is
      # sufficient context — no heading needed"). Only the defensive
      # "must NOT contain the old 'add a game from igdb' phrase" + the
      # input placeholder assertions remain.
      visit games_path
      modal = find("dialog#igdb-search-modal", visible: false)
      expect(modal).to have_no_content("add a game from igdb")
      expect(modal.find("input[type=search]", visible: false)["placeholder"])
        .to eq("search…")
    end

    it "does NOT render a [search] button" do
      visit games_path
      modal = find("dialog#igdb-search-modal", visible: false)
      expect(modal).to have_no_button("[search]")
      expect(modal).to have_no_css('[data-action*="igdb-search-modal#submit"]', visible: false)
    end

    it "renders one bracketed-muted [cancel] link wired to #close" do
      visit games_path
      modal = find("dialog#igdb-search-modal", visible: false)
      expect(modal).to have_css("a.bracketed.bracketed-muted-link", visible: false, count: 1)
      cancel = modal.find("a.bracketed.bracketed-muted-link", visible: false)
      expect(cancel.text).to include("cancel")
      expect(cancel["data-action"]).to eq("click->igdb-search-modal#close")
    end

    it "opts into the .pane-dialog--wide modifier" do
      visit games_path
      modal = find("dialog#igdb-search-modal", visible: false)
      expect(modal[:class].split).to include("pane-dialog--wide")
      # The inline max-width hack is gone.
      expect(modal[:style].to_s).not_to match(/max-width:\s*720px/)
    end
  end

  describe "add flow — eager title in breadcrumb" do
    it "lands on the show page with the IGDB title (not 'Untitled game')" do
      # Drive the search endpoint directly so the result rows render
      # inside the Turbo Frame contract (the JS-driven debounced
      # `frame.src=` assignment is out of rack_test's reach; we exercise
      # the same `GET /games/search?q=…` URL the controller would have
      # fired).
      visit search_games_path(q: "pragmata")
      click_button "[add]"

      game = Game.find_by(igdb_id: 7346)
      expect(game).not_to be_nil
      expect(game.title).to eq("Pragmata")
      expect(current_path).to eq(game_path(game))

      # Breadcrumb on the show page reads the IGDB title — not the
      # `"Untitled game"` default.
      expect(page).to have_content("Pragmata")
      expect(page).not_to have_content("Untitled game")
    end

    it "enqueues GameIgdbSync on add" do
      visit search_games_path(q: "pragmata")
      click_button "[add]"
      game = Game.find_by(igdb_id: 7346)
      expect(GameIgdbSync.jobs.map { |j| j["args"].first }).to include(game.id)
    end

    it "shows the 'game added.' flash notice" do
      # 2026-05-19 — the Rails `[add]` redirect flashes the
      # `games.flash.added` translation, currently `"game added."`.
      # The MCP `game_add_from_igdb` tool still returns the longer
      # `"added; metadata loading in background."` string — unrelated
      # surface; the web flash copy is intentionally shorter.
      visit search_games_path(q: "pragmata")
      click_button "[add]"
      expect(page).to have_content("game added.")
    end
  end
end
