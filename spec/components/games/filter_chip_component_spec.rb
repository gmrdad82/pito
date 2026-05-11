require "rails_helper"

# Phase 27 §01b — Filter chip component.
RSpec.describe Games::FilterChipComponent, type: :component do
  let(:request_path) { "/games" }

  describe "happy: rendering" do
    it "renders an inactive chip with ?filters=ps5 href when active_tokens is empty" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page).to have_css("a.bracketed.filter-chip[href='/games?filters=ps5']")
    end

    it "renders an active chip toggling OFF when the chip is currently active" do
      render_inline(described_class.new(
        token: "ps5", active: true, request_path: request_path, active_tokens: %w[ps5]
      ))
      # toggling off the only active chip drops `filters=` entirely.
      expect(page).to have_css("a.bracketed.filter-chip.chip--active[href='/games']")
    end

    it "preserves OTHER chips when toggling this one" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: %w[owned]
      ))
      expect(page).to have_css("a[href='/games?filters=owned%2Cps5']")
    end

    it "displays 'not owned' (with space) for the not_owned token" do
      render_inline(described_class.new(
        token: "not_owned", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page).to have_text("[not owned]")
    end

    it "displays the canonical token verbatim for everything else" do
      %w[recorded released scheduled owned ps5 switch2 steam gog epic].each do |t|
        rendered = render_inline(described_class.new(
          token: t, active: false, request_path: request_path, active_tokens: []
        ))
        expect(rendered.text).to include(t)
      end
    end

    it "stamps the canonical token on a data attribute (test hook)" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page).to have_css("a[data-filter-token='ps5']")
    end
  end

  describe "sad: invalid input" do
    it "raises ArgumentError when token is not canonical" do
      expect {
        described_class.new(token: "bogus", active: false, request_path: request_path, active_tokens: [])
      }.to raise_error(ArgumentError, /canonical/)
    end

    it "raises ArgumentError when request_path is nil" do
      expect {
        described_class.new(token: "ps5", active: false, request_path: nil, active_tokens: [])
      }.to raise_error(ArgumentError, /request_path/)
    end

    it "raises ArgumentError when request_path is empty" do
      expect {
        described_class.new(token: "ps5", active: false, request_path: "", active_tokens: [])
      }.to raise_error(ArgumentError, /request_path/)
    end
  end

  describe "edge: query string overrides" do
    it "preserves display=list in chip hrefs" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: [],
        query_string_overrides: { display: "list" }
      ))
      href = page.find("a")[:href]
      expect(href).to include("display=list")
      expect(href).to include("filters=ps5")
    end

    it "preserves genre=action in chip hrefs" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: [],
        query_string_overrides: { genre: "action" }
      ))
      href = page.find("a")[:href]
      expect(href).to include("genre=action")
      expect(href).to include("filters=ps5")
    end

    it "omits filters= entirely when toggling drops the last active token" do
      render_inline(described_class.new(
        token: "ps5", active: true, request_path: request_path, active_tokens: %w[ps5],
        query_string_overrides: { display: "list" }
      ))
      href = page.find("a")[:href]
      expect(href).to eq("/games?display=list")
      expect(href).not_to include("filters=")
    end
  end

  describe "edge: active class" do
    it "applies chip--active when active is true" do
      render_inline(described_class.new(
        token: "ps5", active: true, request_path: request_path, active_tokens: %w[ps5]
      ))
      expect(page).to have_css("a.chip--active")
    end

    it "does NOT apply chip--active when active is false" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page).to have_no_css("a.chip--active")
    end
  end

  describe "edge: shape" do
    it "renders a single <a> (not a button or form)" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page).to have_css("a", count: 1)
      expect(page).to have_no_css("button")
      expect(page).to have_no_css("form")
    end
  end

  describe "flaw: defensive surface" do
    it "never emits data-turbo-confirm" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits onclick or inline script attributes" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      html = page.native.to_html
      expect(html).not_to include("onclick")
      expect(html).not_to include("<script")
    end
  end
end
