require "rails_helper"

# Phase 27 §01f — Per-platform ownership editor view.
#
# The page renders a single form posting PATCH to
# `/games/:slug/platform_ownerships`. No JS confirm. The submit and
# cancel actions are bracketed.
RSpec.describe "games/platform_ownerships/edit.html.erb", type: :view do
  let(:game) { create(:game, :synced, title: "Zelda BotW", igdb_slug: "zelda") }
  let(:ps5)  { create(:platform, name: "PS5", slug: "ps5") }

  before do
    game.platforms_available << ps5
    assign(:game, game)
    assign(:ownerships_by_platform,
           { ps5 => game.game_platform_ownerships.new(platform: ps5) })
    assign(:form_error, nil)
  end

  describe "happy: form shape" do
    it "renders a form with PATCH method targeting the ownerships path" do
      render
      expect(rendered).to include(%(action="/games/zelda/platform_ownerships"))
      expect(rendered).to include('name="_method" value="patch"')
    end

    it "carries the [save] submit button" do
      render
      expect(rendered).to match(/\[<span class="bl">save<\/span>\]/)
    end

    it "carries the [cancel] back link to game show" do
      render
      expect(rendered).to include(game_path(game))
      expect(rendered).to match(/\[<span class="bl">cancel<\/span>\]/)
    end

    it "renders the per-platform ownership heading" do
      render
      expect(rendered).to include("per-platform ownership")
    end

    it "renders the editor component fieldset" do
      render
      expect(rendered).to include("platform-ownership-row")
    end
  end

  describe "flaw: no JS confirm anywhere" do
    it "never emits data-turbo-confirm" do
      render
      expect(rendered).not_to include("data-turbo-confirm")
    end

    it "never emits onclick=confirm" do
      render
      expect(rendered).not_to match(/onclick\s*=\s*["']?confirm/i)
    end

    it "the form opts out of turbo but does NOT use a confirm prompt" do
      render
      expect(rendered).to include('data-turbo="false"')
    end
  end

  describe "edge: form_error renders inline" do
    before { assign(:form_error, "_own must be 'yes' or 'no'.") }

    it "shows the form_error inside a text-danger block" do
      render
      expect(rendered).to include("text-danger")
      expect(rendered).to include("_own must be")
    end
  end
end
