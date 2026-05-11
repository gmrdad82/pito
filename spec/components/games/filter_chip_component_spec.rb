require "rails_helper"

# Phase 27 §01b — Filter chip component.
RSpec.describe Games::FilterChipComponent, type: :component do
  let(:request_path) { "/games" }

  describe "happy: rendering" do
    it "renders an inactive chip with ?filters=ps5 href when active_tokens is empty" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page).to have_css("a.filter-chip[href='/games?filters=ps5']")
    end

    it "renders an active chip toggling OFF when the chip is currently active" do
      render_inline(described_class.new(
        token: "ps5", active: true, request_path: request_path, active_tokens: %w[ps5]
      ))
      # toggling off the only active chip drops `filters=` entirely.
      expect(page).to have_css("a.filter-chip.chip--active[href='/games']")
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
      expect(page).to have_text("[ ] not owned")
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

  describe "polish: checkbox-style rendering (2026-05-11)" do
    # Per project convention, filter chips are CHECKBOX-style — they
    # carry a `[ ]` / `[x]` indicator span followed by the label. Same
    # visual shape as the root `FilterChipComponent` used on the
    # notifications inbox. The `[x]` glyph (vs `[ ]`) is the primary
    # active-state cue; `chip--active` adds class hooks for any further
    # styling but introduces no color (red is reserved).
    it "renders `[ ]` (unchecked) and the label in two spans for an inactive chip" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      html = page.native.to_html
      expect(html).to match(%r{<span class="md-check-static">\[ \]</span> <span class="md-check-static-label">ps5</span>})
    end

    it "renders `[x]` (checked) and the label in two spans for an active chip" do
      render_inline(described_class.new(
        token: "ps5", active: true, request_path: request_path, active_tokens: %w[ps5]
      ))
      html = page.native.to_html
      expect(html).to match(%r{<span class="md-check-static">\[x\]</span> <span class="md-check-static-label">ps5</span>})
    end

    %w[recorded released owned scheduled switch2 steam gog epic].each do |t|
      it "renders the canonical token `#{t}` inside `md-check-static-label`" do
        render_inline(described_class.new(
          token: t, active: false, request_path: request_path, active_tokens: []
        ))
        html = page.native.to_html
        expect(html).to include(%(<span class="md-check-static-label">#{t}</span>))
      end
    end

    it "carries the `filter-chip` class (so canonical chip CSS applies)" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page).to have_css("a.filter-chip")
    end

    it "does NOT carry the `bracketed` class (checkbox chips are not bracket-flush links)" do
      render_inline(described_class.new(
        token: "ps5", active: false, request_path: request_path, active_tokens: []
      ))
      expect(page).to have_no_css("a.bracketed")
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
