# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shimmer::TokenComponent, type: :component do
  it "renders the text in a shimmer span with a shared staggered offset bucket" do
    span = render_inline(described_class.new(text: "@gmrdad82")).css("span").first
    expect(span.text).to eq("@gmrdad82")
    expect(span["class"]).to include("pito-token-shimmer")
    expect(span["class"]).to match(/\bpito-shimmer-d\d+\b/)
  end

  it "is deterministic — same text yields the same offset bucket" do
    a = render_inline(described_class.new(text: "#42")).css("span").first
    b = render_inline(described_class.new(text: "#42")).css("span").first
    expect(a["class"]).to eq(b["class"])
  end

  it "appends layout-only extra_class" do
    span = render_inline(described_class.new(text: "#7", extra_class: "tabular-nums")).css("span").first
    expect(span["class"]).to include("tabular-nums")
  end

  describe ".css_class / .html (string-only call sites)" do
    it "builds the same class string as the rendered component" do
      cls = described_class.css_class("##{42}", extra: "tabular-nums")
      expect(cls).to include("pito-token-shimmer")
      expect(cls).to match(/\bpito-shimmer-d\d+\b/)
      expect(cls).to include("tabular-nums")
    end

    it "renders an html-safe span" do
      html = described_class.html("@gmrdad82")
      expect(html).to be_html_safe
      expect(html).to include("pito-token-shimmer")
      expect(html).to include("@gmrdad82")
    end
  end

  it "buckets are bounded by Pito::Shimmer::OFFSETS" do
    bucket = Pito::Shimmer.offset_class("anything")[/\d+/].to_i
    expect(bucket).to be < Pito::Shimmer::OFFSETS
  end

  describe "Pito::Shimmer.offset_class" do
    let(:sequential_ids) { %w[#19 #20 #21 #22 #23] }

    it "is deterministic — same text always yields the same bucket" do
      expect(Pito::Shimmer.offset_class("#42")).to eq(Pito::Shimmer.offset_class("#42"))
    end

    it "keeps all buckets within range" do
      sequential_ids.each do |id|
        bucket = Pito::Shimmer.offset_class(id)[/\d+/].to_i
        expect(bucket).to be < Pito::Shimmer::OFFSETS
      end
    end

    it "scatters sequential ids — not all neighbouring pairs differ by 1" do
      buckets = sequential_ids.map { |id| Pito::Shimmer.offset_class(id)[/\d+/].to_i }
      consecutive_diffs = buckets.each_cons(2).map { |a, b| (a - b).abs }
      expect(consecutive_diffs.any? { |d| d > 1 }).to be(true),
        "expected sequential ids #{sequential_ids.inspect} to scatter (got buckets #{buckets.inspect})"
    end

    it "does not produce a run of all-consecutive buckets for sequential ids" do
      buckets = sequential_ids.map { |id| Pito::Shimmer.offset_class(id)[/\d+/].to_i }.sort
      is_consecutive_run = buckets.each_cons(2).all? { |a, b| b - a <= 1 }
      expect(is_consecutive_run).to be(false),
        "buckets #{buckets.inspect} for #{sequential_ids.inspect} are still a consecutive run"
    end

    describe "seed: kwarg" do
      let(:text) { "@samehandle" }

      it "nil seed produces the same result as the seed-less call (back-compat)" do
        expect(Pito::Shimmer.offset_class(text, seed: nil)).to eq(Pito::Shimmer.offset_class(text))
      end

      it "same text + same seed is stable (deterministic)" do
        a = Pito::Shimmer.offset_class(text, seed: 99)
        b = Pito::Shimmer.offset_class(text, seed: 99)
        expect(a).to eq(b)
      end

      it "same text + different seeds generally land in different buckets" do
        # Scan seeds 1..50 — expect more than one distinct bucket so that
        # repeated @handles in a list are not all synchronised.
        classes = (1..50).map { |i| Pito::Shimmer.offset_class(text, seed: i) }.uniq
        expect(classes.size).to be > 1,
          "expected seeds 1..50 to scatter '#{text}' into more than one bucket"
      end

      it "seeded buckets are still bounded by OFFSETS" do
        (1..50).each do |i|
          bucket = Pito::Shimmer.offset_class(text, seed: i)[/\d+/].to_i
          expect(bucket).to be < Pito::Shimmer::OFFSETS
        end
      end
    end
  end

  describe ".css_class with seed:" do
    it "passes seed through to offset_class" do
      cls_seeded = described_class.css_class("@handle", seed: 7)
      cls_no_seed = described_class.css_class("@handle")
      # Both include the shimmer class...
      expect(cls_seeded).to include("pito-token-shimmer")
      expect(cls_no_seed).to include("pito-token-shimmer")
      # ... but the offset bucket will generally differ.
      offset_seeded   = cls_seeded[/pito-shimmer-d\d+/]
      offset_no_seed  = cls_no_seed[/pito-shimmer-d\d+/]
      expected_with_seed = Pito::Shimmer.offset_class("@handle", seed: 7)
      expect(offset_seeded).to eq(expected_with_seed)
      expect(offset_no_seed).to eq(Pito::Shimmer.offset_class("@handle"))
    end

    it "nil seed leaves the class identical to the seed-less call" do
      expect(described_class.css_class("@handle", seed: nil)).to eq(described_class.css_class("@handle"))
    end
  end

  # Convention (owner 2026-06-29): YELLOW shimmer = clickable; cyan = decorative.
  describe "clickable ⇒ yellow shimmer" do
    it "a prefill (clickable) token renders the yellow clickable shimmer, not cyan" do
      span = render_inline(described_class.new(text: "#42", prefill: "show game #42", submit: true)).css("span").first
      expect(span["class"]).to include("pito-kbd-shimmer")
      expect(span["class"]).not_to include("pito-token-shimmer")
      expect(span["data-controller"]).to eq("pito--chat-prefill")
    end

    it "a decorative (no prefill) token stays cyan and is not clickable" do
      span = render_inline(described_class.new(text: "#42")).css("span").first
      expect(span["class"]).to include("pito-token-shimmer")
      expect(span["class"]).not_to include("pito-kbd-shimmer")
      expect(span["data-controller"]).to be_nil
    end

    it "css_class(clickable: true) picks the yellow shimmer for raw-markup call sites" do
      expect(described_class.css_class("#42", clickable: true)).to include("pito-kbd-shimmer")
      expect(described_class.css_class("#42")).to include("pito-token-shimmer")
    end
  end
end
