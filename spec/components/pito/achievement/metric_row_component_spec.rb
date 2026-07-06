# frozen_string_literal: true

require "rails_helper"

# G127: full-width lane — rail + badges flowing left (no centered towers).
RSpec.describe Pito::Achievement::MetricRowComponent, type: :component do
  let(:video) { create(:video) }

  def unlock!(value)
    Pito::Achievements::Evaluate.call(achievable: video, metric: "views", value:)
    video.achievement_metrics.create!(metric: "views", value:)
  end

  it "renders nothing when the metric has no obtained shinies" do
    node = render_inline(described_class.new(entity: video, metric: "views"))
    expect(node.css(".pito-achievement-metric-row")).to be_empty
  end

  it "renders the rail plus one badge per unlocked threshold, left-aligned" do
    unlock!(5)
    node = render_inline(described_class.new(entity: video, metric: "views"))
    expect(node.css(".pito-shiny-rail")).to be_present
    expect(node.css(".pito-achievement-metric-row__badges .pito-shiny").size).to eq(3) # 1,2,5
    expect(node.css(".pito-achievement-metric-row__badges").first["class"]).to include("justify-start")
    expect(node.css(".pito-achievement-metric-row__badges").first["class"]).not_to include("justify-center")
  end

  it "threads the entity scope into the badges (vid views 5 -> an early stone)" do
    unlock!(5)
    node = render_inline(described_class.new(entity: video, metric: "views"))
    mats = node.css(".pito-achievement-metric-row__badges .pito-shiny").map { |b| b["data-material"] }
    expect(mats).to all(be_in(Pito::Achievement::Tier::STONES))
  end
end
