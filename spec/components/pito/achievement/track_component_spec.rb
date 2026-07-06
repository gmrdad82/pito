# frozen_string_literal: true

require "rails_helper"

# G127: the material RAIL — one tick per ladder step in that step's material.
RSpec.describe Pito::Achievement::TrackComponent, type: :component do
  def render_rail(current_value:, scope: "Video", metric: "views", label: "Views")
    render_inline(described_class.new(label:, current_value:, scope:, metric:))
  end

  it "renders one tick per ladder step, each carrying its material" do
    node  = render_rail(current_value: 0)
    ticks = node.css(".pito-shiny-rail__tick")
    expect(ticks.size).to eq(Pito::Achievement::Tier.series_for(scope: "Video", metric: "views").size)
    expect(ticks.first["data-material"]).to eq("wood")
    expect(ticks.last["data-material"]).to eq("opal")
  end

  it "lights reached ticks, pulses the next, dims the rest" do
    node  = render_rail(current_value: 5)
    ticks = node.css(".pito-shiny-rail__tick")
    expect(ticks[0]["class"]).to include("is-lit")   # 1
    expect(ticks[2]["class"]).to include("is-lit")   # 5
    expect(ticks[3]["class"]).to include("is-next")  # 10
    expect(ticks[4]["class"]).to include("is-dim")   # 20
  end

  it "titles each tick with its compact threshold" do
    node = render_rail(current_value: 0)
    expect(node.css(".pito-shiny-rail__tick").map { |t| t["title"] }.first(4)).to eq(%w[1 2 5 10])
  end

  it "renders channel-subs award steps as square award ticks in metals" do
    node  = render_rail(current_value: 0, scope: "Channel", metric: "subs", label: "Subs")
    award = node.css(".pito-shiny-rail__tick--award")
    expect(award.size).to eq(3)
    expect(award.map { |t| t["data-material"] }).to eq(%w[silver gold diamond])
  end

  it "legends the standing value and the next material" do
    legend = render_rail(current_value: 5).css(".pito-shiny-rail__legend").first.text
    expect(legend).to include("at 5")
    expect(legend).to include("next: 10")
    expect(legend).to match(/\(\w+\)/)
  end

  it "omits the next part when the ladder is complete" do
    legend = render_rail(current_value: 2_000_000).css(".pito-shiny-rail__legend").first.text
    expect(legend).to include("at 2M")
    expect(legend).not_to include("next:")
  end
end
