# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::ShimmerTextComponent do
  describe "basic text rendering" do
    it "renders a span with the pito-network-shimmer class" do
      node = render_inline(described_class.new(text: "hello"))
      expect(node.css("span.pito-network-shimmer")).not_to be_empty
    end

    it "renders the provided text inside the span" do
      node = render_inline(described_class.new(text: "loading…"))
      expect(node.css("span.pito-network-shimmer").first.text).to eq("loading…")
    end

    it "renders no inline style when no delay is given" do
      node = render_inline(described_class.new(text: "dots"))
      span = node.css("span.pito-network-shimmer").first
      expect(span["style"].to_s).to be_empty
    end
  end

  describe "dots / input-width variant" do
    it "renders the repeated dot text inside the shimmer span" do
      dots = ". " * 30
      node = render_inline(described_class.new(text: dots))
      expect(node.css("span.pito-network-shimmer").first.text).to eq(dots)
    end

    it "works with an arbitrary repeat count" do
      node = render_inline(described_class.new(text: "." * 10))
      expect(node.css("span.pito-network-shimmer")).not_to be_empty
    end
  end

  describe "extra_classes" do
    it "appends extra CSS classes to the span" do
      node = render_inline(described_class.new(text: "●", extra_classes: "shrink-0"))
      span = node.css("span").first
      expect(span["class"]).to include("pito-network-shimmer")
      expect(span["class"]).to include("shrink-0")
    end

    it "renders without extra classes when none are given" do
      node = render_inline(described_class.new(text: "●"))
      span = node.css("span.pito-network-shimmer").first
      expect(span["class"].strip).to eq("pito-network-shimmer")
    end
  end

  describe "delay / stagger mechanism" do
    it "sets animation-delay inline style when delay is provided" do
      node = render_inline(described_class.new(text: "●", delay: "0.30s"))
      span = node.css("span.pito-network-shimmer").first
      expect(span["style"]).to include("animation-delay:0.30s")
    end

    it "renders all five STEP_DELAYS stagger values without error" do
      %w[0s 0.15s 0.30s 0.45s 0.60s].each do |delay|
        node = render_inline(described_class.new(text: "●", extra_classes: "shrink-0", delay:))
        span = node.css("span.pito-network-shimmer").first
        expect(span["style"]).to include("animation-delay:#{delay}")
      end
    end

    it "does not render a style attribute when delay is blank" do
      node = render_inline(described_class.new(text: "●", delay: ""))
      span = node.css("span.pito-network-shimmer").first
      expect(span["style"].to_s).to be_empty
    end
  end

  describe "#css_classes helper" do
    it "returns only pito-network-shimmer when no extra classes" do
      comp = described_class.new(text: "x")
      expect(comp.css_classes).to eq("pito-network-shimmer")
    end

    it "joins pito-network-shimmer and extra_classes" do
      comp = described_class.new(text: "x", extra_classes: "ml-1 shrink-0")
      expect(comp.css_classes).to eq("pito-network-shimmer ml-1 shrink-0")
    end
  end

  describe "#inline_style helper" do
    it "returns nil when no delay given" do
      comp = described_class.new(text: "x")
      expect(comp.inline_style).to be_nil
    end

    it "returns the animation-delay string when delay is set" do
      comp = described_class.new(text: "x", delay: "0.45s")
      expect(comp.inline_style).to eq("animation-delay:0.45s")
    end
  end

  describe "import-sidebar dots usage" do
    it "renders a dots row equivalent to the sidebar shimmer indicator" do
      # The games_import sidebar uses text: \". \" * 30
      node = render_inline(described_class.new(text: ". " * 30))
      span = node.css("span.pito-network-shimmer").first
      expect(span).not_to be_nil
      expect(span.text.length).to be > 20
    end
  end

  describe "import step dot usage (broadcast)" do
    it "renders the step indicator dot with shrink-0 and a stagger delay" do
      node = render_inline(
        described_class.new(text: "●", extra_classes: "shrink-0", delay: "0.15s")
      )
      span = node.css("span.pito-network-shimmer.shrink-0").first
      expect(span).not_to be_nil
      expect(span["style"]).to include("animation-delay:0.15s")
      expect(span.text).to eq("●")
    end
  end
end
