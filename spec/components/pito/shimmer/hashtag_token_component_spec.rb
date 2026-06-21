# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shimmer::HashtagTokenComponent, type: :component do
  it "renders the text in a blue→purple hashtag shimmer span with a shared offset" do
    span = render_inline(described_class.new(text: "#chi-4450")).css("span").first
    expect(span.text).to eq("#chi-4450")
    expect(span["class"]).to include("pito-hashtag-shimmer")
    expect(span["class"]).to match(/\bpito-shimmer-d\d+\b/)
  end

  it "is deterministic — same text yields the same offset bucket" do
    a = render_inline(described_class.new(text: "#alpha-1")).css("span").first
    b = render_inline(described_class.new(text: "#alpha-1")).css("span").first
    expect(a["class"]).to eq(b["class"])
  end

  it "appends layout-only extra_class" do
    span = render_inline(described_class.new(text: "#x", extra_class: "ml-2")).css("span").first
    expect(span["class"]).to include("ml-2")
  end

  describe ".css_class / .html" do
    it "builds the hashtag shimmer class string" do
      cls = described_class.css_class("#chi-4450")
      expect(cls).to include("pito-hashtag-shimmer")
      expect(cls).to match(/\bpito-shimmer-d\d+\b/)
    end

    it "renders an html-safe span" do
      html = described_class.html("#chi-4450")
      expect(html).to be_html_safe
      expect(html).to include("pito-hashtag-shimmer")
      expect(html).to include("#chi-4450")
    end
  end
end
