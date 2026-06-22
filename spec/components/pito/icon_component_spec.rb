# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::IconComponent do
  # ── Inline SVG structure ──────────────────────────────────────

  describe "#call — inline SVG output" do
    let(:comp) { described_class.new(name: "thumbs-up", label: "likes") }

    it "renders an <svg> element" do
      html = render_inline(comp).to_html
      expect(html).to include("<svg")
    end

    it "preserves the Lucide 24×24 viewBox" do
      html = render_inline(comp).to_html
      expect(html).to include('viewBox="0 0 24 24"')
    end

    it "carries stroke=currentColor so the icon inherits text colour" do
      html = render_inline(comp).to_html
      expect(html).to include('stroke="currentColor"')
    end

    it "carries fill=none (outline style, no fill)" do
      html = render_inline(comp).to_html
      expect(html).to include('fill="none"')
    end
  end

  # ── Sizing — must stay ≤ 1em (14px base) ─────────────────────

  describe "sizing" do
    let(:comp) { described_class.new(name: "thumbs-up") }

    it "sets width to 1em" do
      html = render_inline(comp).to_html
      expect(html).to include('width="1em"')
    end

    it "sets height to 1em" do
      html = render_inline(comp).to_html
      expect(html).to include('height="1em"')
    end

    it "adds the pito-icon CSS class (controls display + vertical-align)" do
      html = render_inline(comp).to_html
      expect(html).to include('class="pito-icon"')
    end

    it "does not emit a hardcoded pixel width/height" do
      html = render_inline(comp).to_html
      expect(html).not_to match(/width="\d+px?"/)
      expect(html).not_to match(/height="\d+px?"/)
    end
  end

  # ── Accessibility ─────────────────────────────────────────────

  describe "accessibility — labelled icon" do
    let(:comp) { described_class.new(name: "thumbs-up", label: "likes") }

    it "sets role=img" do
      html = render_inline(comp).to_html
      expect(html).to include('role="img"')
    end

    it "sets aria-label to the supplied label" do
      html = render_inline(comp).to_html
      expect(html).to include('aria-label="likes"')
    end

    it "HTML-escapes quotes in the label (prevents attribute injection)" do
      # A bare " in the label would close the aria-label attribute and allow
      # injecting new HTML attributes (e.g. onload=). CGI.escapeHTML encodes
      # " → &quot; so the label stays inside the attribute context.
      # We assert via the DOM API: no onload attribute on the <svg> element.
      xss = described_class.new(name: "thumbs-up", label: 'x" onload="alert(1)')
      node = render_inline(xss)
      svg  = node.at_css("svg")
      expect(svg["onload"]).to be_nil
      expect(svg["aria-label"]).to eq('x" onload="alert(1)')
    end
  end

  describe "accessibility — decorative icon (no label)" do
    let(:comp) { described_class.new(name: "thumbs-up") }

    it "sets aria-hidden=true" do
      html = render_inline(comp).to_html
      expect(html).to include('aria-hidden="true"')
    end

    it "does not set role or aria-label" do
      html = render_inline(comp).to_html
      expect(html).not_to include('role="img"')
      expect(html).not_to include("aria-label")
    end
  end

  # ── All three vendored icons render without error ─────────────

  describe "vendored icon set" do
    %w[thumbs-up thumbs-down message-square].each do |name|
      it "renders #{name} as an inline SVG" do
        html = render_inline(described_class.new(name:)).to_html
        expect(html).to include("<svg")
        expect(html).to include('viewBox="0 0 24 24"')
        expect(html).to include('stroke="currentColor"')
      end
    end
  end

  # ── Missing icon — graceful failure ──────────────────────────

  describe "missing icon" do
    it "raises ArgumentError mentioning the unknown name" do
      comp = described_class.new(name: "nonexistent-icon")
      expect { render_inline(comp) }.to raise_error(ArgumentError, /nonexistent-icon/)
    end
  end

  # ── Class-level caching ───────────────────────────────────────

  describe "svg_cache" do
    it "returns the identical string object on repeated lookups (no extra disk reads)" do
      first  = described_class.svg_cache["thumbs-up"]
      second = described_class.svg_cache["thumbs-up"]
      expect(first).to equal(second)
    end

    it "does not memoize a failed lookup (re-raises on every call)" do
      cache = described_class.svg_cache
      2.times do
        expect { cache["still-nonexistent"] }.to raise_error(ArgumentError)
      end
    end
  end
end
