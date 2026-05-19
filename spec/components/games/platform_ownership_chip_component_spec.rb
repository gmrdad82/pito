require "rails_helper"

# Wave C4 / Wave F consolidation — `Games::PlatformOwnershipChipComponent`.
#
# Per-platform ownership toggle chip rendered in the /games/:id
# LEFT-pane ownership section. Wraps a `Platforms::ChipComponent`-styled
# button in a form posting to
# `Games::PlatformOwnershipsController#update` with the FULL set of
# owned-platform ids, with the toggled platform's id added or removed
# (the existing editor endpoint accepts the full set; a dedicated
# per-platform endpoint is a deferred polish slice).
#
# Brand color (per `Platforms::ChipComponent::SLUG_BRAND`):
#   - `ps`     → `#003791`
#   - `switch` → `#E60012`
#   - `steam`  → `#00ADEE`
#
# Render gate (`render?`): only the three canonical chip slugs
# (`ps` / `switch` / `steam`) render, AND only when a `Platform` row
# matching the slug exists. Anything else returns no markup.
#
# Slug-fixture note: `Platform` has `before_validation :set_slug` (via
# FriendlyId) which regenerates `slug` from `name` on save, so passing
# `slug:` to the factory is clobbered. Match the
# `OwnershipMatrixComponent` spec pattern — `update_column(:slug, …)`
# AFTER `create` to force the canonical chip slug into the row.
RSpec.describe Games::PlatformOwnershipChipComponent, type: :component do
  # Helper: create a Platform row whose persisted slug is exactly the
  # value the chip component looks up (`ps` / `switch` / `steam`).
  # Use update_column to bypass the FriendlyId before_validation hook.
  def platform_with_slug(name:, slug:)
    p = create(:platform, name: name)
    p.update_column(:slug, slug)
    p
  end

  describe "#render? gating" do
    it "renders when slug is a canonical chip slug and Platform exists" do
      ps_platform = platform_with_slug(name: "PS Brand", slug: "ps")
      game = create(:game, title: "RenderGate")
      component = described_class.new(game: game, slug: "ps")
      expect(component.platform).to eq(ps_platform)
      expect(component.render?).to be true
    end

    it "does NOT render when slug is not in SLUG_BRAND (e.g. `xbox`)" do
      game = build_stubbed(:game)
      component = described_class.new(game: game, slug: "xbox")
      expect(component.render?).to be false
    end

    it "does NOT render when slug is canonical but Platform row is missing" do
      # No Platform with slug `switch` exists in this example.
      game = create(:game)
      component = described_class.new(game: game, slug: "switch")
      expect(component.platform).to be_nil
      expect(component.render?).to be false
    end

    it "does NOT render when slug is empty" do
      game = build_stubbed(:game)
      component = described_class.new(game: game, slug: "")
      expect(component.render?).to be false
    end

    it "produces empty output when render? is false (xbox)" do
      game = build_stubbed(:game)
      result = render_inline(described_class.new(game: game, slug: "xbox"))
      expect(result.to_html.strip).to eq("")
    end
  end

  describe "#owned? lookup" do
    let!(:ps) { platform_with_slug(name: "PS Brand", slug: "ps") }
    let(:game) { create(:game, title: "OwnedLookup") }

    it "is true when a `game_platform_ownership` row exists for the chip's Platform" do
      create(:game_platform_ownership, game: game, platform: ps)
      component = described_class.new(game: game, slug: "ps")
      expect(component.owned?).to be true
    end

    it "is false when no ownership row exists for the chip's Platform" do
      component = described_class.new(game: game, slug: "ps")
      expect(component.owned?).to be false
    end

    it "is false when Platform row for the slug does not exist" do
      # `switch` slug is unknown — no Platform row, so owned? is false.
      component = described_class.new(game: game, slug: "switch")
      expect(component.owned?).to be false
    end

    it "ignores ownership rows for OTHER platforms" do
      other = platform_with_slug(name: "Steam Brand", slug: "steam")
      create(:game_platform_ownership, game: game, platform: other)
      component = described_class.new(game: game, slug: "ps")
      expect(component.owned?).to be false
    end
  end

  describe "#toggled_ids add/remove math" do
    let!(:ps)     { platform_with_slug(name: "PS Brand",     slug: "ps") }
    let!(:switch) { platform_with_slug(name: "Switch Brand", slug: "switch") }
    let!(:steam)  { platform_with_slug(name: "Steam Brand",  slug: "steam") }
    let(:game)    { create(:game, title: "ToggleMath") }

    it "ADDS the platform id when not currently owned (empty start)" do
      component = described_class.new(game: game, slug: "ps")
      expect(component.toggled_ids).to eq([ ps.id ])
    end

    it "ADDS the platform id to an existing owned set" do
      create(:game_platform_ownership, game: game, platform: steam)
      component = described_class.new(game: game, slug: "ps")
      expect(component.toggled_ids).to contain_exactly(ps.id, steam.id)
    end

    it "REMOVES the platform id when currently owned" do
      create(:game_platform_ownership, game: game, platform: ps)
      create(:game_platform_ownership, game: game, platform: steam)
      component = described_class.new(game: game, slug: "ps")
      expect(component.toggled_ids).to eq([ steam.id ])
    end

    it "REMOVES the platform id and yields an empty set when it was the only one" do
      create(:game_platform_ownership, game: game, platform: ps)
      component = described_class.new(game: game, slug: "ps")
      expect(component.toggled_ids).to eq([])
    end

    it "does not mutate the underlying owned_platform_ids array" do
      create(:game_platform_ownership, game: game, platform: ps)
      component = described_class.new(game: game, slug: "ps")
      original = component.owned_platform_ids.dup
      component.toggled_ids
      expect(component.owned_platform_ids).to eq(original)
    end
  end

  describe "#label and #color (brand-color tinting per slug)" do
    before do
      platform_with_slug(name: "PS Brand",     slug: "ps")
      platform_with_slug(name: "Switch Brand", slug: "switch")
      platform_with_slug(name: "Steam Brand",  slug: "steam")
    end

    let(:game) { create(:game) }

    it "labels `ps` as `PS` with brand color `#003791`" do
      c = described_class.new(game: game, slug: "ps")
      expect(c.label).to eq("PS")
      expect(c.color).to eq("#003791")
    end

    it "labels `switch` as `Switch` with brand color `#E60012`" do
      c = described_class.new(game: game, slug: "switch")
      expect(c.label).to eq("Switch")
      expect(c.color).to eq("#E60012")
    end

    it "labels `steam` as `Steam` with brand color `#00ADEE`" do
      c = described_class.new(game: game, slug: "steam")
      expect(c.label).to eq("Steam")
      expect(c.color).to eq("#00ADEE")
    end
  end

  describe "#chip_color branches" do
    let!(:ps) { platform_with_slug(name: "PS Brand", slug: "ps") }
    let(:game) { create(:game) }

    it "uses the brand color when owned" do
      create(:game_platform_ownership, game: game, platform: ps)
      component = described_class.new(game: game, slug: "ps")
      expect(component.chip_color).to eq("#003791")
    end

    it "uses the `--color-muted` token when not owned" do
      component = described_class.new(game: game, slug: "ps")
      expect(component.chip_color).to eq("var(--color-muted)")
    end
  end

  describe "happy: render shape — owned" do
    let!(:ps)    { platform_with_slug(name: "PS Brand",    slug: "ps") }
    let!(:steam) { platform_with_slug(name: "Steam Brand", slug: "steam") }
    let(:game)   { create(:game, title: "OwnedRender") }

    before do
      create(:game_platform_ownership, game: game, platform: ps)
      create(:game_platform_ownership, game: game, platform: steam)
      render_inline(described_class.new(game: game, slug: "ps"))
    end

    it "renders the form with PATCH method" do
      form = page.find("form.ownership-chip-form")
      expect(form["method"]).to eq("post")
      expect(form).to have_css("input[name=_method][value=patch]", visible: false)
    end

    it "posts to the game-scoped platform_ownerships endpoint" do
      form = page.find("form.ownership-chip-form")
      expect(form["action"]).to end_with("/platform_ownerships")
    end

    it "renders a submit button styled as a brand chip" do
      expect(page).to have_css("button.platform-chip.platform-chip--md.ownership-chip-button")
    end

    it "renders the bracketed `[PS]` label" do
      expect(page).to have_text("[PS]")
    end

    it "applies the brand color inline" do
      button = page.find("button.platform-chip")
      expect(button["style"]).to include("color: #003791")
    end

    it "carries an `owned — click to remove` title" do
      button = page.find("button.platform-chip")
      expect(button["title"]).to eq("owned on PS — click to remove")
    end

    it "submits hidden ids WITHOUT the toggled platform (remove on click)" do
      ids = page.all("input[name='platform_owned_ids[]']", visible: false)
                .map { |el| el["value"].to_i }
      expect(ids).to contain_exactly(steam.id)
      expect(ids).not_to include(ps.id)
    end
  end

  describe "happy: render shape — not owned" do
    let!(:ps)    { platform_with_slug(name: "PS Brand",    slug: "ps") }
    let!(:steam) { platform_with_slug(name: "Steam Brand", slug: "steam") }
    let(:game)   { create(:game, title: "NotOwnedRender") }

    before do
      # Owns Steam but NOT PS; the PS chip should render as not-owned.
      create(:game_platform_ownership, game: game, platform: steam)
      render_inline(described_class.new(game: game, slug: "ps"))
    end

    it "renders the muted color inline" do
      button = page.find("button.platform-chip")
      expect(button["style"]).to include("color: var(--color-muted)")
    end

    it "carries a `not owned — click to add` title" do
      button = page.find("button.platform-chip")
      expect(button["title"]).to eq("not owned on PS — click to add")
    end

    it "submits hidden ids WITH the toggled platform (add on click)" do
      ids = page.all("input[name='platform_owned_ids[]']", visible: false)
                .map { |el| el["value"].to_i }
      expect(ids).to contain_exactly(ps.id, steam.id)
    end
  end

  describe "edge: empty toggled set keeps the array param alive" do
    let!(:ps) { platform_with_slug(name: "PS Brand", slug: "ps") }
    let(:game) { create(:game, title: "EmptyToggle") }

    before do
      # User owns ONLY PS; toggling PS empties the set.
      create(:game_platform_ownership, game: game, platform: ps)
      render_inline(described_class.new(game: game, slug: "ps"))
    end

    it "emits a single blank hidden field so platform_owned_ids[] still posts" do
      blanks = page.all("input[name='platform_owned_ids[]']", visible: false)
                   .map { |el| el["value"] }
      expect(blanks).to eq([ "" ])
    end
  end

  describe "flaw: no JS confirm or destructive styling" do
    let!(:ps) { platform_with_slug(name: "PS Brand", slug: "ps") }
    let(:game) { create(:game) }

    before do
      create(:game_platform_ownership, game: game, platform: ps)
      render_inline(described_class.new(game: game, slug: "ps"))
    end

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits a destructive class" do
      expect(page.native.to_html).not_to include("text-danger")
    end

    it "never emits the destructive red token `#cc0000`" do
      expect(page.native.to_html).not_to include("#cc0000")
    end

    it "disables Turbo for this form (full-page redirect-back posture)" do
      form = page.find("form.ownership-chip-form")
      expect(form["data-turbo"]).to eq("false")
    end
  end
end
