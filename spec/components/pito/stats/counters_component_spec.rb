# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stats::CountersComponent, type: :component do
  def render_for(metrics, align: :left)
    render_inline(described_class.new(metrics: metrics, align: align))
  end

  it "renders '<compact value> <Word>' for word metrics (subs/vids/views)" do
    node = render_for([ { key: :subs, value: 2345 }, { key: :vids, value: 3 }, { key: :views, value: 454 } ])
    text = node.text.gsub(/\s+/, " ").strip
    expect(text).to include("2.3K Subs")
    expect(text).to include("3 Vids")
    expect(text).to include("454 Views")
  end

  it "renders '<count> + icon' for likes (thumbs-up) and comments (message-square)" do
    node = render_for([ { key: :likes, value: 4 }, { key: :comments, value: 0 } ])
    likes_cell    = node.css(".pito-stats-counters__cell").first
    comments_cell = node.css(".pito-stats-counters__cell").last

    # Count text present, no word label for icon metrics.
    expect(likes_cell.text).to include("4")
    expect(likes_cell.text).not_to include("Likes")
    expect(comments_cell.text).to include("0")
    expect(comments_cell.text).not_to include("Comments")

    # Inline icons rendered with their accessible labels.
    expect(likes_cell.at_css("svg")).to be_present
    expect(likes_cell.at_css("svg")["aria-label"]).to eq("Likes")
    expect(comments_cell.at_css("svg")["aria-label"]).to eq("Comments")
  end

  it "renders icons through the canonical .pito-icon hook (align/gap/stroke live there, not per call-site)" do
    node = render_for([ { key: :likes, value: 4 }, { key: :comments, value: 0 } ])
    icons = node.css("svg")
    expect(icons).not_to be_empty
    # Every icon carries the single-source class and none sets an ad-hoc inline
    # style or margin — the gap before the number comes from `.pito-icon` alone.
    icons.each do |svg|
      expect(svg["class"].to_s.split).to include("pito-icon")
      expect(svg["style"]).to be_nil
    end
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
