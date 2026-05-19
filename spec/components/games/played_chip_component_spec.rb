require "rails_helper"

# Wave C4 / Wave F consolidation — `Games::PlayedChipComponent`.
#
# Single `[played]` chip rendered in the /games/:id LEFT-pane
# ownership section (visual-state only; the editable surface stays on
# the game edit page until a dedicated toggle slice ships). The chip
# is colored when `game.played_at` is present and muted otherwise.
#
# This component does NOT submit a form and does NOT take a slug —
# `played_at` is a SINGULAR property on the game record (the played
# *platform* lives on the `OwnershipMatrixComponent` per-row checkbox,
# not here).
RSpec.describe Games::PlayedChipComponent, type: :component do
  describe "#played? predicate" do
    it "returns true when `played_at` is set" do
      game = build_stubbed(:game, played_at: 3.days.ago.to_date)
      component = described_class.new(game: game)
      expect(component.played?).to be true
    end

    it "returns false when `played_at` is nil" do
      game = build_stubbed(:game, played_at: nil)
      component = described_class.new(game: game)
      expect(component.played?).to be false
    end
  end

  describe "#chip_color branches" do
    it "returns the `--color-active` token (with green fallback) when played" do
      game = build_stubbed(:game, played_at: 1.day.ago.to_date)
      component = described_class.new(game: game)
      expect(component.chip_color).to eq("var(--color-active, #228b22)")
    end

    it "returns the `--color-muted` token when not played" do
      game = build_stubbed(:game, played_at: nil)
      component = described_class.new(game: game)
      expect(component.chip_color).to eq("var(--color-muted)")
    end
  end

  describe "happy: render shape — played" do
    # `played_at` is a DATE column on `games` (see db/schema.rb).
    # `to_fs(:long)` on a Date yields e.g. `"June 01, 2025"`.
    let(:played_at) { Date.new(2025, 6, 1) }
    let(:game) { build_stubbed(:game, played_at: played_at) }

    before { render_inline(described_class.new(game: game)) }

    it "renders the chip with the shared platform-chip class" do
      expect(page).to have_css("span.platform-chip")
    end

    it "renders the md size modifier class" do
      expect(page).to have_css("span.platform-chip--md")
    end

    it "renders the static ownership-chip class (no form)" do
      expect(page).to have_css("span.ownership-chip-static")
    end

    it "renders the bracketed `[played]` label" do
      expect(page).to have_text("[played]")
    end

    it "renders inline color matching the active chip color" do
      span = page.find("span.platform-chip")
      expect(span["style"]).to include("color: var(--color-active, #228b22)")
    end

    it "carries a played-on title with the long-form date" do
      span = page.find("span.platform-chip")
      expect(span["title"]).to eq("played on #{played_at.to_fs(:long)}")
    end

    it "never emits a form element (visual-only, non-functional)" do
      expect(page).not_to have_css("form")
    end

    it "never emits an input element" do
      expect(page).not_to have_css("input")
    end
  end

  describe "happy: render shape — not played" do
    let(:game) { build_stubbed(:game, played_at: nil) }

    before { render_inline(described_class.new(game: game)) }

    it "renders the chip with the shared platform-chip class" do
      expect(page).to have_css("span.platform-chip")
    end

    it "renders the bracketed `[played]` label even when not played" do
      # Label is constant; state is conveyed via color + title.
      expect(page).to have_text("[played]")
    end

    it "renders inline muted color" do
      span = page.find("span.platform-chip")
      expect(span["style"]).to include("color: var(--color-muted)")
    end

    it "carries a not-yet-played title" do
      span = page.find("span.platform-chip")
      expect(span["title"]).to eq("not yet played")
    end

    it "never emits a form element" do
      expect(page).not_to have_css("form")
    end
  end

  describe "edge: played_at today still counts as played" do
    it "treats Date.current as played (boundary)" do
      today = Date.current
      game = build_stubbed(:game, played_at: today)
      render_inline(described_class.new(game: game))
      span = page.find("span.platform-chip")
      expect(span["style"]).to include("var(--color-active")
      expect(span["title"]).to start_with("played on ")
    end
  end

  describe "flaw: no JS confirm or destructive styling" do
    let(:game) { build_stubbed(:game, played_at: nil) }

    before { render_inline(described_class.new(game: game)) }

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits a destructive class" do
      expect(page.native.to_html).not_to include("text-danger")
    end

    it "never emits the destructive red token `#cc0000`" do
      # `--color-active` resolves to a green tone; red is reserved for
      # destructive actions only (per design.md / CLAUDE.md hard rule).
      expect(page.native.to_html).not_to include("#cc0000")
    end
  end
end
