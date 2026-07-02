# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Detail::CardComponent, type: :component do
  let(:channel) { create(:channel) }
  let(:metrics) { [ { key: :views, value: 42 } ] }

  def render_card(shinies: [], intro: nil)
    render_inline(described_class.new(bem: "pito-test-detail", stat_counter_metrics: metrics,
                                      shinies:, intro:)) do |card|
      card.with_image { '<div class="pito-test-detail__cover">img</div>'.html_safe }
      card.with_body  { '<div class="right-content">rows</div>'.html_safe }
    end
  end

  it "renders the two-column shell with the caller's BEM block" do
    node = render_card
    expect(node.css(".pito-test-detail").size).to eq(1)
    expect(node.css(".pito-test-detail__left").size).to eq(1)
    expect(node.css(".pito-test-detail__right .right-content").size).to eq(1)
  end

  it "renders the image slot inside the left column" do
    node = render_card
    expect(node.css(".pito-test-detail__left .pito-test-detail__cover").text).to eq("img")
  end

  it "renders the intro with the timestamp slot anchor when given" do
    node = render_card(intro: "hello <b>you</b>")
    intro = node.css(".pito-test-detail__intro")
    expect(intro.css("[data-pito-ts-slot]").size).to eq(1)
    expect(intro.css("b").text).to eq("you")
  end

  it "omits the intro row when intro is nil" do
    expect(render_card.css(".pito-test-detail__intro")).to be_empty
  end

  it "renders the Stats kv-row with the counters" do
    node = render_card
    expect(node.css(".pito-test-detail__stats.pito-detail-stats").size).to eq(1)
    expect(node.css(".pito-test-detail__stats-heading").size).to eq(1)
  end

  it "omits the Shinies row when there are no shinies" do
    expect(render_card.css(".pito-test-detail__shinies")).to be_empty
  end

  it "renders one badge per shiny when given" do
    shiny = create(:achievement, achievable: channel, metric: "views",
                                 threshold: 1_000, unlocked_at: 1.day.ago)
    node = render_card(shinies: [ shiny ])
    expect(node.css(".pito-test-detail__shinies-heading").size).to eq(1)
    expect(node.css(".pito-test-detail__shinies").size).to eq(1)
  end
end
