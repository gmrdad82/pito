# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shimmer::SubjectComponent, type: :component do
  it "renders the text in a subject-shimmer span with a shared staggered offset bucket" do
    span = render_inline(described_class.new(text: "Elden Ring")).css("span").first
    expect(span.text).to eq("Elden Ring")
    expect(span["class"]).to include("pito-subject-shimmer")
    expect(span["class"]).to match(/\bpito-shimmer-d\d+\b/)
  end

  it "is deterministic — same text yields the same offset bucket" do
    a = render_inline(described_class.new(text: "Hades")).css("span").first
    b = render_inline(described_class.new(text: "Hades")).css("span").first
    expect(a["class"]).to eq(b["class"])
  end

  it "appends layout-only extra_class" do
    span = render_inline(described_class.new(text: "Hades", extra_class: "whitespace-nowrap")).css("span").first
    expect(span["class"]).to include("whitespace-nowrap")
  end

  it "escapes user-derived subject text (no raw markup leaks)" do
    html = render_inline(described_class.new(text: "<script>x</script>")).to_html
    expect(html).to include("&lt;script&gt;")
    expect(html).not_to include("<script>")
  end

  describe ".css_class / .html (string-only call sites)" do
    it "builds a class string with the family + a shared offset bucket" do
      cls = described_class.css_class("Elden Ring", extra: "whitespace-nowrap")
      expect(cls).to include("pito-subject-shimmer")
      expect(cls).to match(/\bpito-shimmer-d\d+\b/)
      expect(cls).to include("whitespace-nowrap")
    end

    it "renders an html-safe span" do
      html = described_class.html("Elden Ring")
      expect(html).to be_html_safe
      expect(html).to include("pito-subject-shimmer")
      expect(html).to include("Elden Ring")
    end

    it "the offset bucket is bounded by Pito::Shimmer::OFFSETS" do
      bucket = described_class.css_class("anything")[/pito-shimmer-d(\d+)/, 1].to_i
      expect(bucket).to be < Pito::Shimmer::OFFSETS
    end
  end

  describe "seed: kwarg" do
    it "passes seed through to offset_class (nil seed == seed-less)" do
      expect(described_class.css_class("Hades", seed: nil)).to eq(described_class.css_class("Hades"))
    end

    it "varies the offset bucket as the seed varies" do
      classes = (1..50).map { |i| described_class.css_class("Hades", seed: i)[/pito-shimmer-d\d+/] }.uniq
      expect(classes.size).to be > 1,
        "expected seeds 1..50 to scatter 'Hades' into more than one offset bucket"
    end
  end
end
