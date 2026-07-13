# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shimmer::HashtagTokenComponent, type: :component do
  it "renders the text as muted text (item 7 — no shimmer)" do
    span = render_inline(described_class.new(text: "#chi-4450")).css("span").first
    expect(span.text).to eq("#chi-4450")
    expect(span["class"]).to include("text-fg-default")
    expect(span["class"]).not_to include("shimmer")
  end

  it "appends layout-only extra_class" do
    span = render_inline(described_class.new(text: "#x", extra_class: "ml-2")).css("span").first
    expect(span["class"]).to include("ml-2")
  end

  describe ".css_class / .html" do
    it "builds the muted class string" do
      cls = described_class.css_class("#chi-4450")
      expect(cls).to include("text-fg-default")
      expect(cls).not_to include("shimmer")
    end

    it "renders an html-safe span" do
      html = described_class.html("#chi-4450")
      expect(html).to be_html_safe
      expect(html).to include("text-fg-default")
      expect(html).to include("#chi-4450")
    end
  end
end
