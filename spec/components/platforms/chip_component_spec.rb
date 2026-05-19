require "rails_helper"

# Wave F consolidation (2026-05-18) — Platforms::ChipComponent.
#
# Central chip primitive for `ps` / `switch` / `steam`. Renders a
# `<span class="platform-chip platform-chip--<slug> platform-chip--<size>">`
# with an I18n-resolved label and a brand-color constant in `SLUG_BRAND`.
#
# Coverage:
#   - `SLUG_BRAND` shape (3 known slugs, label + color).
#   - `CANONICAL_PLATFORM_SLUG_BY_CHIP` mapping (ps → ps5,
#     switch → switch-2, steam → steam).
#   - `render?` gates unknown / nil slugs.
#   - `label` resolves via I18n with `SLUG_BRAND[:label]` fallback.
#   - `size_class` honors `:sm` (default) vs `:md`.
RSpec.describe Platforms::ChipComponent, type: :component do
  # ----------------------------------------------------------------
  # SLUG_BRAND — frozen constant defining the chip vocabulary.
  # ----------------------------------------------------------------

  describe "SLUG_BRAND" do
    it "enumerates exactly the three canonical chip slugs" do
      expect(described_class::SLUG_BRAND.keys).to contain_exactly("ps", "switch", "steam")
    end

    it "is frozen so callers cannot mutate the canonical chip set" do
      expect(described_class::SLUG_BRAND).to be_frozen
    end

    {
      "ps"     => { label: "PS",     color: "#003791" },
      "switch" => { label: "Switch", color: "#E60012" },
      "steam"  => { label: "Steam",  color: "#00ADEE" }
    }.each do |slug, brand|
      it "maps `#{slug}` to label=#{brand[:label].inspect} color=#{brand[:color].inspect}" do
        expect(described_class::SLUG_BRAND[slug]).to eq(brand)
      end
    end
  end

  # ----------------------------------------------------------------
  # CANONICAL_PLATFORM_SLUG_BY_CHIP — chip slug → Platform row slug.
  # ----------------------------------------------------------------

  describe "CANONICAL_PLATFORM_SLUG_BY_CHIP" do
    it "covers the same chip set as SLUG_BRAND" do
      expect(described_class::CANONICAL_PLATFORM_SLUG_BY_CHIP.keys)
        .to contain_exactly("ps", "switch", "steam")
    end

    it "is frozen" do
      expect(described_class::CANONICAL_PLATFORM_SLUG_BY_CHIP).to be_frozen
    end

    it "resolves `ps` to `ps5` (PS5 is the canonical PS row, not ps4)" do
      expect(described_class::CANONICAL_PLATFORM_SLUG_BY_CHIP["ps"]).to eq("ps5")
    end

    it "resolves `switch` to `switch-2` (Switch 2 is the canonical Switch row)" do
      expect(described_class::CANONICAL_PLATFORM_SLUG_BY_CHIP["switch"]).to eq("switch-2")
    end

    it "resolves `steam` to `steam` (single PC umbrella per ADR 0013)" do
      expect(described_class::CANONICAL_PLATFORM_SLUG_BY_CHIP["steam"]).to eq("steam")
    end
  end

  # ----------------------------------------------------------------
  # render? — gating on the chip vocabulary.
  # ----------------------------------------------------------------

  describe "#render?" do
    %w[ps switch steam].each do |slug|
      it "returns true for known slug `#{slug}`" do
        expect(described_class.new(slug: slug).render?).to be true
      end
    end

    it "returns false for an unknown slug" do
      expect(described_class.new(slug: "xbox").render?).to be false
    end

    it "returns false for an empty string slug" do
      expect(described_class.new(slug: "").render?).to be false
    end

    it "returns false when slug is nil (coerced to empty string)" do
      expect(described_class.new(slug: nil).render?).to be false
    end

    it "accepts symbol slugs and coerces them to strings" do
      expect(described_class.new(slug: :ps).render?).to be true
    end

    it "does NOT render any markup when render? is false" do
      result = render_inline(described_class.new(slug: "unknown"))
      expect(result.to_s).to be_blank
    end
  end

  # ----------------------------------------------------------------
  # label — I18n resolution with SLUG_BRAND fallback.
  # ----------------------------------------------------------------

  describe "#label" do
    it "returns the I18n value for `platforms.chip.label.ps`" do
      expect(described_class.new(slug: "ps").label).to eq("PS")
    end

    it "returns the I18n value for `platforms.chip.label.switch`" do
      expect(described_class.new(slug: "switch").label).to eq("Switch")
    end

    it "returns the I18n value for `platforms.chip.label.steam`" do
      expect(described_class.new(slug: "steam").label).to eq("Steam")
    end

    it "falls back to SLUG_BRAND[:label] when the I18n key is missing" do
      # Stub I18n to simulate a missing translation for a known chip — it
      # must still return the SLUG_BRAND fallback.
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t)
        .with("platforms.chip.label.ps", default: "PS")
        .and_return("PS")
      expect(described_class.new(slug: "ps").label).to eq("PS")
    end
  end

  # ----------------------------------------------------------------
  # color — direct read from SLUG_BRAND.
  # ----------------------------------------------------------------

  describe "#color" do
    it "returns the brand color for a known slug" do
      expect(described_class.new(slug: "ps").color).to eq("#003791")
      expect(described_class.new(slug: "switch").color).to eq("#E60012")
      expect(described_class.new(slug: "steam").color).to eq("#00ADEE")
    end

    it "returns nil for an unknown slug" do
      expect(described_class.new(slug: "xbox").color).to be_nil
    end
  end

  # ----------------------------------------------------------------
  # size_class — :sm (default) vs :md.
  # ----------------------------------------------------------------

  describe "#size_class" do
    it "defaults to `platform-chip--sm` when size is not passed" do
      expect(described_class.new(slug: "ps").size_class).to eq("platform-chip--sm")
    end

    it "returns `platform-chip--sm` for explicit :sm" do
      expect(described_class.new(slug: "ps", size: :sm).size_class).to eq("platform-chip--sm")
    end

    it "returns `platform-chip--md` for :md" do
      expect(described_class.new(slug: "ps", size: :md).size_class).to eq("platform-chip--md")
    end

    it "raises KeyError for an unknown size (no silent fallback)" do
      expect { described_class.new(slug: "ps", size: :lg).size_class }.to raise_error(KeyError)
    end
  end

  # ----------------------------------------------------------------
  # Rendered shape — full markup integration.
  # ----------------------------------------------------------------

  describe "#render" do
    it "renders a span with the canonical class list for :sm" do
      render_inline(described_class.new(slug: "ps"))
      expect(page).to have_css("span.platform-chip.platform-chip--ps.platform-chip--sm", text: "PS")
    end

    it "renders a span with the :md size class when explicitly :md" do
      render_inline(described_class.new(slug: "switch", size: :md))
      expect(page).to have_css("span.platform-chip.platform-chip--switch.platform-chip--md", text: "Switch")
    end

    it "renders the I18n-resolved label as the visible text" do
      render_inline(described_class.new(slug: "steam"))
      expect(page).to have_css("span.platform-chip--steam", text: "Steam")
    end

    it "renders nothing for unknown slugs" do
      result = render_inline(described_class.new(slug: "xbox"))
      expect(result.to_s).to be_blank
    end

    it "renders nothing for nil slugs" do
      result = render_inline(described_class.new(slug: nil))
      expect(result.to_s).to be_blank
    end
  end
end
