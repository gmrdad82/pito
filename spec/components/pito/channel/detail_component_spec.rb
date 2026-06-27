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

  describe "YouTube Channel link row" do
    it "renders the 'YouTube Channel' key" do
      expect(render_card.text).to include("YouTube Channel")
    end

    it "renders a link to the youtube.com/@handle URL" do
      node = render_card
      link = node.css("a[href*='youtube.com/@gmrdad82']").first
      expect(link).to be_present
      expect(link["href"]).to eq("https://www.youtube.com/@gmrdad82")
    end

    it "opens the YouTube Channel link in a new tab" do
      node = render_card
      link = node.css("a[href*='youtube.com/@gmrdad82']").first
      expect(link["target"]).to eq("_blank")
      expect(link["rel"]).to include("noopener")
    end

    it "displays the URL without the https:// scheme" do
      node = render_card
      link = node.css("a[href*='youtube.com/@gmrdad82']").first
      expect(link.text.strip).to eq("youtube.com/@gmrdad82")
    end
  end

  describe "YouTube Studio link row" do
    it "renders the 'YouTube Studio' key" do
      expect(render_card.text).to include("YouTube Studio")
    end

    it "renders a link to the studio.youtube.com/channel/<id> URL" do
      node = render_card
      link = node.css("a[href*='studio.youtube.com']").first
      expect(link).to be_present
      expect(link["href"]).to include("studio.youtube.com/channel/")
    end

    it "opens the YouTube Studio link in a new tab" do
      node = render_card
      link = node.css("a[href*='studio.youtube.com']").first
      expect(link["target"]).to eq("_blank")
      expect(link["rel"]).to include("noopener")
    end

    it "displays the URL without the https:// scheme" do
      node = render_card
      link = node.css("a[href*='studio.youtube.com']").first
      expect(link.text.strip).to start_with("studio.youtube.com/channel/")
    end
  end
end
