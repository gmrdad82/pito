require "rails_helper"

RSpec.describe Pito::GamesReleasingPanelComponent, type: :component do
  subject(:rendered) { render_inline(described_class.new) }

  let(:root) { rendered.css("section.pito-panel").first }

  # Isolate each example from dev-seed upcoming games.
  before do
    Game.where("release_date > ?", Date.current).delete_all
  end

  it "renders the canonical pito-panel section wrapper" do
    expect(root).to be_present
    expect(root["class"]).to include("pito-panel")
    expect(root["class"]).to include("pito-panel--games-releasing")
  end

  it "renders the rescued pito-pane chrome with the i18n title" do
    title = I18n.t("tui.home.panels.games_releasing.title")
    expect(title).to eq("upcoming games")
    expect(root["class"]).to include("pane")
    expect(root["class"]).to include("pito-pane")
    header = rendered.css(".pito-pane__title").first
    expect(header).to be_present
    expect(header.text.strip).to eq(title)
  end

  it "wires the tui-panel-cable Stimulus controller" do
    expect(root["data-controller"]).to include("tui-panel-cable")
  end

  it "emits the canonical cable name + screen data values" do
    expect(root["data-tui-panel-cable-name-value"]).to eq("games_releasing")
    expect(root["data-tui-panel-cable-screen-value"]).to eq("home")
  end

  it "registers the panel as a tui-cursor target" do
    expect(root["data-tui-cursor-target"]).to eq("panel")
  end

  describe "panel-level [ ] sync action (2026-05-24)" do
    it "renders the Tui::SyncIndicatorComponent with target=home.upcoming_games" do
      sync = rendered.css("button.tui-sync-word--target").first
      expect(sync).to be_present
      expect(sync["data-tui-sync-indicator-target-value"]).to eq("home.upcoming_games")
    end

    it "carries data-tui-focusable-key=upcoming_games_sync" do
      sync = rendered.css("button.tui-sync-word--target").first
      expect(sync["data-tui-focusable-key"]).to eq("upcoming_games_sync")
    end
  end

  describe "PANEL_NAME" do
    it "matches the canonical Pito::PanelChannel allowlist entry" do
      expect(described_class::PANEL_NAME).to eq(:games_releasing)
      expect(Pito::PanelChannel::ALLOWED_PANELS).to include(described_class::PANEL_NAME.to_s)
    end
  end

  describe "empty state (no upcoming games in window)" do
    it "emits upcoming_games_sync as the sole focusable" do
      expect(root["data-tui-panel-focusables-value"]).to eq("upcoming_games_sync")
      expect(root["data-tui-panel-keybinds-value"]).to eq("{}")
    end

    it "renders the i18n empty-state hint inside the panel fieldset" do
      placeholder = rendered.css(".tui-panel-fieldset .pito-panel__placeholder").first
      expect(placeholder).to be_present
      expect(placeholder.text.strip).to eq(
        I18n.t("tui.home.panels.games_releasing.empty")
      )
    end

    it "does NOT render a shelf row when there are no upcoming games" do
      expect(rendered.css(".upcoming-tile-shelf__row")).to be_empty
    end
  end

  describe "populated state (scheduled games in the next 30 days)" do
    let!(:soon) do
      g = Game.new(
        title: "Soon Game",
        igdb_slug: "soon-game-test",
        release_date: Date.current + 5.days,
        release_year: (Date.current + 5.days).year
      )
      g.save!(validate: false)
      g
    end

    let!(:later) do
      g = Game.new(
        title: "Later Game",
        igdb_slug: "later-game-test",
        release_date: Date.current + 20.days,
        release_year: (Date.current + 20.days).year
      )
      g.save!(validate: false)
      g
    end

    let!(:too_far) do
      g = Game.new(
        title: "Too Far",
        igdb_slug: "too-far-test",
        release_date: Date.current + 90.days,
        release_year: (Date.current + 90.days).year
      )
      g.save!(validate: false)
      g
    end

    it "renders one tile per game inside the upcoming window" do
      tiles = rendered.css(".upcoming-tile-shelf__row .upcoming-tile")
      titles = tiles.map { |t| t["title"] }
      expect(titles).to include("Soon Game", "Later Game")
      expect(titles).not_to include("Too Far")
    end

    it "orders tiles by release_date ASC (soonest first)" do
      tiles = rendered.css(".upcoming-tile-shelf__row .upcoming-tile")
      expect(tiles.first["title"]).to eq("Soon Game")
      expect(tiles.last["title"]).to eq("Later Game")
    end

    it "contributes per-tile focusable keys after upcoming_games_sync" do
      focusables = root["data-tui-panel-focusables-value"].split(",")
      expect(focusables.first).to eq("upcoming_games_sync")
      expect(focusables).to include("upcoming_#{soon.id}")
      expect(focusables).to include("upcoming_#{later.id}")
      expect(focusables[1..]).to eq([ "upcoming_#{soon.id}", "upcoming_#{later.id}" ])
    end

    it "wires the fieldset's horizontal-axis scroll indicator" do
      fieldset = rendered.css(".tui-panel-fieldset").first
      expect(fieldset).to be_present
      expect(fieldset["class"]).to include("tui-panel-fieldset--horizontal")
      expect(fieldset["class"]).to include("upcoming-tile-shelf")
      expect(fieldset["data-tui-scroll-indicator-axis-value"]).to eq("horizontal")
    end

    it "renders the bottom-edge scroll indicator glyphs" do
      expect(rendered.css(".tui-scroll-indicator--left").text).to include("◀")
      expect(rendered.css(".tui-scroll-indicator--right").text).to include("▶")
      handle = rendered.css(".tui-scroll-indicator--horizontal.tui-scroll-indicator--handle")
      expect(handle.text).to include("▬")
    end
  end
end
