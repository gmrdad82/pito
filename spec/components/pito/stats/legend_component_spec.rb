# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stats::LegendComponent, type: :component do
  it "renders '<ABBR> <word>' entries, comma-separated (S subs, D vids, V views)" do
    node = render_inline(described_class.new(metrics: [ :subs, :vids, :views ], align: :center))
    expect(node.text.gsub(/\s+/, " ").strip).to eq("S subs, D vids, V views")
  end

  it "applies the alignment class" do
    expect(render_inline(described_class.new(metrics: [ :subs ], align: :center)).css("p.text-center")).not_to be_empty
    expect(render_inline(described_class.new(metrics: [ :views ], align: :left)).css("p.text-left")).not_to be_empty
  end

  it "renders nothing when empty" do
    expect(render_inline(described_class.new(metrics: [])).to_html.strip).to eq("")
  end
end
