# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Channel::DetailComponent, type: :component do
  let(:channel) { create(:channel, handle: "gmrdad82", title: "GMR Dad", description: "Stories.\nMore.", video_count: 42) }

  before do
    Pito::Stats.set(channel, :subscribers, 1500)
    Pito::Stats.set(channel, :views, 2_300_000)
  end

  def render_card(ch = channel)
    render_inline(described_class.new(channel: ch))
  end

  it "renders the handle (cyan) and title in the kv-table" do
    node = render_card
    expect(node.text).to include("@gmrdad82").and include("GMR Dad")
  end

  it "renders the Subs / Views / Vids word counters" do
    text = render_card.css(".pito-stats-counters").text
    expect(text).to include("Subs").and include("Views").and include("Vids")
  end

  it "renders the description, wrapped (whitespace-pre-wrap)" do
    node = render_card
    expect(node.text).to include("Stories.")
    expect(node.at_css(".whitespace-pre-wrap")).to be_present
  end

  it "omits the description row when the channel has none" do
    channel.update!(description: nil)
    expect(render_card.text).not_to include("Description")
  end

  it "renders an absolute Last sync at stamp when synced" do
    channel.update!(last_synced_at: Time.zone.local(2026, 6, 26, 14, 30))
    expect(render_card.text).to include("26-06-2026 14:30")
  end

  it "renders the em-dash for a never-synced channel" do
    channel.update!(last_synced_at: nil)
    node = render_card
    expect(node.text).to include("Last sync at")
    expect(node.text).to include("—")
  end

  it "shows the no-avatar placeholder when no avatar is attached" do
    expect(render_card.text).to include("No avatar")
  end
end
