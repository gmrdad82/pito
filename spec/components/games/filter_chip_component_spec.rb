require "rails_helper"

# Phase 27 v2 spec 06 — Filter chip (checkbox-style, v2).
#
# Renders `[ ] label` (unchecked) / `[x] label` (checked) per the
# `checked:` arg. The anchor href reflects the post-toggle URL so
# JS-off users navigate to the right page on click; the
# `games-filter` Stimulus controller intercepts the click in the
# JS-on path.
RSpec.describe Games::FilterChipComponent, type: :component do
  let(:universe) { Games::FiltersHelper::TOKEN_UNIVERSE }

  describe "happy: rendering" do
    it "renders an unchecked chip with the post-toggle href (DEFAULT set when toggling lands on default)" do
      # DEFAULT_CHECKED_TOKENS = universe MINUS `played` (user-locked
      # 2026-05-17 — engagement axis opt-in). Start from DEFAULT minus
      # `ps` (so 6 chips checked: every default token except ps).
      # Toggling the unchecked `ps` chip adds it back → set equals
      # DEFAULT_CHECKED_TOKENS → helper emits the canonical bare `/games`.
      render_inline(described_class.new(
        token: "ps", checked: false,
        checked_tokens: Games::FiltersHelper::DEFAULT_CHECKED_TOKENS - [ "ps" ]
      ))
      expect(page).to have_css("a.filter-chip[href='/games']")
    end

    it "renders an unchecked chip whose toggle URL adds the chip when others are checked" do
      render_inline(described_class.new(
        token: "ps", checked: false,
        checked_tokens: [ "owned" ]
      ))
      # Toggling ps grows the set to [owned, ps] → in universe order
      # → owned,ps. Helper emits the literal CSV (no URL encoding of
      # the comma — `,` is a reserved-but-allowed character).
      expect(page).to have_css("a.filter-chip[href='/games?filters=owned,ps']")
    end

    it "renders a checked chip whose toggle URL removes the chip" do
      render_inline(described_class.new(
        token: "ps", checked: true,
        checked_tokens: %w[owned ps]
      ))
      expect(page).to have_css("a.filter-chip.chip--active[href='/games?filters=owned']")
    end

    it "renders the [ ] indicator for an unchecked chip" do
      render_inline(described_class.new(
        token: "ps", checked: false, checked_tokens: []
      ))
      expect(page).to have_text("[ ] PS")
    end

    it "renders the [x] indicator for a checked chip" do
      render_inline(described_class.new(
        token: "ps", checked: true, checked_tokens: %w[ps]
      ))
      expect(page).to have_text("[x] PS")
    end

    # Platform-token chips render the PLATFORM_LABELS short label
    # (Switch, PS, Steam). GoG + Epic were collapsed
    # into Steam in the 2026-05-17 PC store collapse.
    {
      "ps"     => "PS",
      "switch" => "Switch",
      "steam"  => "Steam"
    }.each do |token, label|
      it "renders the #{token} chip with label #{label.inspect}" do
        rendered = render_inline(described_class.new(
          token: token, checked: false, checked_tokens: []
        ))
        expect(rendered.text).to include(label)
      end
    end

    it "renders status / ownership tokens verbatim" do
      %w[released scheduled owned wishlist played].each do |t|
        rendered = render_inline(described_class.new(
          token: t, checked: false, checked_tokens: []
        ))
        expect(rendered.text).to include(t)
      end
    end

    it "stamps the canonical token on a data attribute (Stimulus hook)" do
      render_inline(described_class.new(
        token: "ps", checked: false, checked_tokens: []
      ))
      expect(page).to have_css("a[data-filter-token='ps']")
    end

    it "stamps `data-games-filter-target=chip` so the controller can collect chips" do
      render_inline(described_class.new(
        token: "ps", checked: false, checked_tokens: []
      ))
      expect(page).to have_css("a[data-games-filter-target='chip']")
    end

    it "stamps `data-action` so Stimulus intercepts clicks" do
      render_inline(described_class.new(
        token: "ps", checked: false, checked_tokens: []
      ))
      action_attr = page.find("a")["data-action"]
      expect(action_attr).to include("click->games-filter#toggle")
    end
  end

  describe "cascade `data-implied` attribute (played only)" do
    it "stamps data-implied with 'released,owned' on the played chip" do
      render_inline(described_class.new(
        token: "played", checked: false, checked_tokens: []
      ))
      implied = page.find("a")["data-implied"]
      expect(implied).to eq("released,owned")
    end

    it "does NOT stamp data-implied on the released chip" do
      render_inline(described_class.new(
        token: "released", checked: false, checked_tokens: []
      ))
      expect(page.find("a")["data-implied"]).to be_nil
    end

    it "does NOT stamp data-implied on any platform chip" do
      %w[ps switch steam].each do |t|
        render_inline(described_class.new(
          token: t, checked: false, checked_tokens: []
        ))
        expect(page.find("a")["data-implied"]).to be_nil
      end
    end

    it "does NOT stamp data-implied on the owned / wishlist chips" do
      %w[owned wishlist].each do |t|
        render_inline(described_class.new(
          token: t, checked: false, checked_tokens: []
        ))
        expect(page.find("a")["data-implied"]).to be_nil
      end
    end
  end

  describe "sad: invalid input" do
    it "raises ArgumentError when token is not in the v2 universe" do
      expect {
        described_class.new(
          token: "bogus", checked: false, checked_tokens: []
        )
      }.to raise_error(ArgumentError, /canonical/)
    end

    it "raises ArgumentError on the legacy xbox token (not in v2)" do
      expect {
        described_class.new(
          token: "xbox", checked: false, checked_tokens: []
        )
      }.to raise_error(ArgumentError, /canonical/)
    end

    it "raises ArgumentError on the legacy gog token (collapsed into steam 2026-05-17)" do
      expect {
        described_class.new(
          token: "gog", checked: false, checked_tokens: []
        )
      }.to raise_error(ArgumentError, /canonical/)
    end

    it "raises ArgumentError on the legacy epic token (collapsed into steam 2026-05-17)" do
      expect {
        described_class.new(
          token: "epic", checked: false, checked_tokens: []
        )
      }.to raise_error(ArgumentError, /canonical/)
    end

    it "raises ArgumentError on the legacy not_owned token (not in v2)" do
      expect {
        described_class.new(
          token: "not_owned", checked: false, checked_tokens: []
        )
      }.to raise_error(ArgumentError, /canonical/)
    end

    it "raises ArgumentError on the legacy recorded token (not in v2)" do
      expect {
        described_class.new(
          token: "recorded", checked: false, checked_tokens: []
        )
      }.to raise_error(ArgumentError, /canonical/)
    end

    it "raises ArgumentError when request_path is empty" do
      expect {
        described_class.new(
          token: "ps", checked: false, checked_tokens: [], request_path: ""
        )
      }.to raise_error(ArgumentError, /request_path/)
    end
  end

  describe "edge: chip--active class" do
    it "applies chip--active when checked is true" do
      render_inline(described_class.new(
        token: "ps", checked: true, checked_tokens: %w[ps]
      ))
      expect(page).to have_css("a.chip--active")
    end

    it "does NOT apply chip--active when checked is false" do
      render_inline(described_class.new(
        token: "ps", checked: false, checked_tokens: []
      ))
      expect(page).to have_no_css("a.chip--active")
    end
  end

  describe "edge: shape" do
    it "renders a single <a> (no button, no form, no <script>)" do
      render_inline(described_class.new(
        token: "ps", checked: false, checked_tokens: []
      ))
      expect(page).to have_css("a", count: 1)
      expect(page).to have_no_css("button")
      expect(page).to have_no_css("form")
      expect(page.native.to_html).not_to include("<script")
    end
  end

  describe "flaw: defensive surface" do
    it "never emits data-turbo-confirm" do
      render_inline(described_class.new(
        token: "ps", checked: false, checked_tokens: []
      ))
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits onclick / inline script" do
      render_inline(described_class.new(
        token: "ps", checked: false, checked_tokens: []
      ))
      html = page.native.to_html
      expect(html).not_to include("onclick")
      expect(html).not_to include("<script")
    end
  end
end
