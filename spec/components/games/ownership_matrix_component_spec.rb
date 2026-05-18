require "rails_helper"

# Lane C surface coverage — `Games::OwnershipMatrixComponent`.
#
# The component renders the 3-row PS / Switch / Steam ownership matrix on
# `/games/:id`. Each row carries inline `[owned]` and `[played]` checkboxes
# wired to `Games::OwnershipTogglesController` via auto-submit forms, plus
# Stimulus data attributes (`ownership-cascade` targets) for the
# client-side cascade logic.
#
# FN1+FN2 / FK reshape notes (2026-05-18):
#   - Always render all 3 rows (PS / Switch / Steam) — NOT intersected
#     against IGDB's `platforms_available`. The user's manual ownership
#     is the source of truth for the matrix.
#   - Switch chip resolves to the `switch-2` Platform slug (canonical
#     pick is Switch 2, hyphenated per FriendlyId).
#   - Active state has NO color — `[ ]` vs `[x]` is the sole visual
#     signal; modifier classes stay for Stimulus hooks but carry no
#     visual rule.
RSpec.describe Games::OwnershipMatrixComponent, type: :component do
  let(:game) { create(:game, title: "Test Game") }

  describe "happy: always renders 3 rows" do
    before { render_inline(described_class.new(game: game)) }

    it "renders exactly 3 ownership rows" do
      expect(page).to have_css(".ownership-matrix__row", count: 3)
    end

    it "labels the rows PS, Switch, Steam (in SLUG_BRAND order)" do
      labels = page.all(".ownership-matrix__platform").map(&:text).map(&:strip)
      expect(labels).to eq(%w[PS Switch Steam])
    end

    it "renders 2 checkboxes per row (owned + played)" do
      expect(page).to have_css("input[type=checkbox]", count: 6)
    end

    it "renders an `owned` checkbox per row" do
      expect(page).to have_css("input[type=checkbox][data-ownership-cascade-target=owned]", count: 3)
    end

    it "renders a `played` checkbox per row" do
      expect(page).to have_css("input[type=checkbox][data-ownership-cascade-target=played]", count: 3)
    end
  end

  describe "happy: always renders 3 rows even when IGDB lists no platforms" do
    # Per FK fix — applicable_slugs no longer intersects with
    # IGDB-reported platforms. Even a freshly-created game with zero
    # `game_platforms` rows shows all three matrix rows so the user
    # can mark ownership without waiting on IGDB metadata.
    it "renders all 3 rows regardless of platforms_available" do
      expect(game.platforms_available).to be_empty
      render_inline(described_class.new(game: game))
      expect(page).to have_css(".ownership-matrix__row", count: 3)
    end
  end

  describe "happy: owned state per platform" do
    let!(:ps5) { create(:platform, name: "PS5", slug: "ps5") }

    before do
      create(:game_platform_ownership, game: game, platform: ps5)
      render_inline(described_class.new(game: game))
    end

    it "checks the PS row's owned checkbox" do
      checkbox = page.find("input[data-ownership-cascade-target=owned][data-ownership-cascade-platform=ps]")
      expect(checkbox[:checked]).to be_truthy
    end

    it "leaves the Switch row's owned checkbox unchecked" do
      checkbox = page.find("input[data-ownership-cascade-target=owned][data-ownership-cascade-platform=switch]")
      expect(checkbox[:checked]).to be_falsey
    end

    it "leaves the Steam row's owned checkbox unchecked" do
      checkbox = page.find("input[data-ownership-cascade-target=owned][data-ownership-cascade-platform=steam]")
      expect(checkbox[:checked]).to be_falsey
    end

    it "applies the `--owned` modifier class on the PS row" do
      expect(page).to have_css(".ownership-matrix__toggle--owned")
    end
  end

  describe "happy: played state singular across the matrix" do
    let!(:ps5) { create(:platform, name: "PS5", slug: "ps5") }

    before do
      game.update!(played_platform: ps5)
      render_inline(described_class.new(game: game))
    end

    it "checks the PS row's played checkbox" do
      checkbox = page.find("input[data-ownership-cascade-target=played][data-ownership-cascade-platform=ps]")
      expect(checkbox[:checked]).to be_truthy
    end

    it "leaves the Switch row's played checkbox unchecked" do
      checkbox = page.find("input[data-ownership-cascade-target=played][data-ownership-cascade-platform=switch]")
      expect(checkbox[:checked]).to be_falsey
    end

    it "leaves the Steam row's played checkbox unchecked" do
      checkbox = page.find("input[data-ownership-cascade-target=played][data-ownership-cascade-platform=steam]")
      expect(checkbox[:checked]).to be_falsey
    end

    it "applies the `--played` modifier class on the PS row" do
      expect(page).to have_css(".ownership-matrix__toggle--played")
    end

    it "only ever renders one `--played` modifier class (singular constraint)" do
      expect(page).to have_css(".ownership-matrix__toggle--played", count: 1)
    end
  end

  describe "happy: Switch chip resolves to switch-2 slug (FN2-fix)" do
    let!(:switch_2) do
      p = create(:platform, name: "Nintendo Switch 2")
      p.update_column(:slug, "switch-2")
      p
    end

    before do
      create(:game_platform_ownership, game: game, platform: switch_2)
      render_inline(described_class.new(game: game))
    end

    it "checks the Switch row when ownership is recorded on the `switch-2` Platform" do
      checkbox = page.find("input[data-ownership-cascade-target=owned][data-ownership-cascade-platform=switch]")
      expect(checkbox[:checked]).to be_truthy
    end

    it "does NOT resolve a hyphenless `switch2` slug" do
      # Sanity probe — a `switch2` (no hyphen) row exists but is NOT
      # the canonical pick. Ownership on it must NOT light up the
      # Switch chip's checkbox.
      hyphenless = create(:platform, name: "switch2-noncanonical")
      hyphenless.update_column(:slug, "switch2")
      other_game = create(:game, title: "Other Game")
      create(:game_platform_ownership, game: other_game, platform: hyphenless)

      render_inline(described_class.new(game: other_game))
      checkbox = page.find("input[data-ownership-cascade-target=owned][data-ownership-cascade-platform=switch]")
      expect(checkbox[:checked]).to be_falsey
    end
  end

  describe "happy: Steam chip resolves to canonical steam Platform" do
    let!(:steam) { create(:platform, name: "Steam", slug: "steam") }

    before do
      create(:game_platform_ownership, game: game, platform: steam)
      render_inline(described_class.new(game: game))
    end

    it "checks the Steam row's owned checkbox" do
      checkbox = page.find("input[data-ownership-cascade-target=owned][data-ownership-cascade-platform=steam]")
      expect(checkbox[:checked]).to be_truthy
    end
  end

  describe "happy: Stimulus cascade controller wiring" do
    before { render_inline(described_class.new(game: game)) }

    it "wraps the matrix in the `ownership-cascade` controller" do
      expect(page).to have_css("[data-controller=ownership-cascade]")
    end

    it "labels every owned checkbox with `data-platform` attributes" do
      slugs = page.all("input[data-ownership-cascade-target=owned]")
                  .map { |el| el["data-ownership-cascade-platform"] }
      expect(slugs).to contain_exactly("ps", "switch", "steam")
    end

    it "labels every played checkbox with `data-platform` attributes" do
      slugs = page.all("input[data-ownership-cascade-target=played]")
                  .map { |el| el["data-ownership-cascade-platform"] }
      expect(slugs).to contain_exactly("ps", "switch", "steam")
    end

    it "binds `ownedChanged` action on every owned checkbox" do
      page.all("input[data-ownership-cascade-target=owned]").each do |el|
        expect(el["data-action"]).to include("change->ownership-cascade#ownedChanged")
      end
    end

    it "binds `playedChanged` action on every played checkbox" do
      page.all("input[data-ownership-cascade-target=played]").each do |el|
        expect(el["data-action"]).to include("change->ownership-cascade#playedChanged")
      end
    end

    it "binds `auto-submit#submit` on every checkbox" do
      page.all("input[type=checkbox]").each do |el|
        expect(el["data-action"]).to include("change->auto-submit#submit")
      end
    end
  end

  describe "happy: form submit targets per row" do
    before { render_inline(described_class.new(game: game)) }

    it "posts owned PATCH to /games/:id/ownership_toggles/:platform" do
      form = page.find("form[action$='/ownership_toggles/ps']")
      expect(form["method"]).to eq("post")
      expect(form).to have_css("input[name=_method][value=patch]", visible: false)
    end

    it "posts played PATCH to /games/:id/played_toggles/:platform" do
      form = page.find("form[action$='/played_toggles/ps']")
      expect(form["method"]).to eq("post")
      expect(form).to have_css("input[name=_method][value=patch]", visible: false)
    end
  end

  describe "flaw: no JS confirm or destructive styling" do
    before { render_inline(described_class.new(game: game)) }

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits data-confirm" do
      expect(page.native.to_html).not_to match(/data-confirm[^-]/)
    end

    it "never emits a destructive class" do
      expect(page.native.to_html).not_to include("text-danger")
    end
  end

  describe "flaw: active modifier class is a hook, not a style (FN2-fix)" do
    let!(:ps5) { create(:platform, name: "PS5", slug: "ps5") }

    before do
      create(:game_platform_ownership, game: game, platform: ps5)
      game.update!(played_platform: ps5)
      render_inline(described_class.new(game: game))
    end

    # Verifies the FN2-fix: the modifier classes still emit (kept for
    # the Stimulus cascade controller's class hooks), but no inline
    # color is applied here — color rules now live in CSS only via
    # the design token surface. The component must not leak any
    # `style="color:..."` attribute or inline brand color.
    it "renders the --owned modifier class without inline color" do
      label = page.find("label.ownership-matrix__toggle--owned")
      expect(label["style"]).to be_nil.or eq("")
    end

    it "renders the --played modifier class without inline color" do
      label = page.find("label.ownership-matrix__toggle--played")
      expect(label["style"]).to be_nil.or eq("")
    end

    it "does not emit hard-coded brand colors inline" do
      # SLUG_BRAND PS color = `#003791`; the matrix component must not
      # inline brand colors on active rows (FN2-fix drops colorization).
      expect(page.native.to_html).not_to include("#003791")
      expect(page.native.to_html).not_to include("#E60012")
      expect(page.native.to_html).not_to include("#00ADEE")
    end
  end

  describe "yes/no boundary contract" do
    # Hard rule: external boundary booleans serialize as `yes`/`no`.
    # The checkbox `value="yes"` posts `enabled=yes` on flip and the
    # controller's `coerce_boolean` treats unchecked (no param) as
    # `enabled=no`. Verify the input value never drifts to `true` /
    # `1` / `on`.
    before { render_inline(described_class.new(game: game)) }

    it "uses `value=yes` on every checkbox" do
      page.all("input[type=checkbox]").each do |el|
        expect(el["value"]).to eq("yes")
      end
    end

    it "never uses `value=true` or `value=1` on checkboxes" do
      page.all("input[type=checkbox]").each do |el|
        expect(el["value"]).not_to eq("true")
        expect(el["value"]).not_to eq("1")
        expect(el["value"]).not_to eq("on")
      end
    end
  end
end
