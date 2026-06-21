# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stats::CountersComponent, type: :component do
  def render_for(metrics, align: :left)
    render_inline(described_class.new(metrics: metrics, align: align))
  end

  it "renders '<compact value> <ABBR>' per metric (S/D/V)" do
    node = render_for([ { key: :subs, value: 2345 }, { key: :vids, value: 3 }, { key: :views, value: 454 } ])
    text = node.text.gsub(/\s+/, " ").strip
    expect(text).to include("2.3K S")
    expect(text).to include("3 D")
    expect(text).to include("454 V")
  end

  it "separates cells with the inline middot" do
    expect(render_for([ { key: :views, value: 1 }, { key: :likes, value: 2 } ]).text).to include("·")
  end

  it "applies the center alignment class" do
    expect(render_for([ { key: :views, value: 1 } ], align: :center).css(".pito-stats-counters.text-center")).not_to be_empty
  end

  it "applies the left alignment class" do
    expect(render_for([ { key: :views, value: 1 } ], align: :left).css(".pito-stats-counters.text-left")).not_to be_empty
  end

  it "renders nothing for empty metrics" do
    expect(render_inline(described_class.new(metrics: [])).to_html.strip).to eq("")
  end
end
