# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Table::LinkValueComponent do
  def render_link(url:, **opts)
    render_inline(described_class.new(url:, **opts))
  end

  it "renders an external link with the scheme stripped from the text" do
    node = render_link(url: "https://www.youtube.com/@gmrdad82")
    a = node.css("a").first
    expect(a["href"]).to eq("https://www.youtube.com/@gmrdad82")
    expect(a.text).to eq("youtube.com/@gmrdad82")
    expect(a["target"]).to eq("_blank")
    expect(a["rel"]).to eq("noopener")
  end

  it "wears the yellow shimmer + a per-url stagger offset by default" do
    node = render_link(url: "https://youtube.com/@a")
    klass = node.css("a").first["class"]
    expect(klass).to include("text-yellow").and include("pito-action-shimmer")
    expect(klass).to match(/pito-shimmer-d\d+/)
  end

  it "staggers two different urls out of phase" do
    a = render_link(url: "https://youtube.com/@a").css("a").first["class"][/pito-shimmer-d\d+/]
    b = render_link(url: "https://studio.youtube.com/channel/UC2").css("a").first["class"][/pito-shimmer-d\d+/]
    expect([ a, b ]).to all(be_present)
  end
end
