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

  it "renders the handle as a clickable prefill token + the title in the kv-table" do
    node = render_card
    expect(node.text).to include("@gmrdad82").and include("GMR Dad")
    # 13.12: the @handle is a clickable token that prefills + submits `show channel @handle`
    handle = node.css("[data-pito--chat-prefill-text-value='show channel @gmrdad82']").first
    expect(handle).to be_present
    expect(handle["data-pito--chat-prefill-submit-value"]).to eq("true")
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

  it "shows no avatar anywhere when none is attached (no left spot, no kv-table row)" do
    node = render_card
    expect(node.at_css(".pito-channel-detail__avatar img")).to be_nil
    expect(node.at_css("img.pito-channel-detail__avatar-inline")).to be_nil
  end

  describe "banner + avatar placement" do
    let(:jpeg) { Vips::Image.black(8, 8).cast(:uchar).bandjoin([ 0, 0 ]).jpegsave_buffer }

    def attach_avatar
      channel.avatar.attach(io: StringIO.new(jpeg), filename: "avatar-#{channel.id}.jpg", content_type: "image/jpeg")
    end

    def attach_banner
      channel.banner.attach(io: StringIO.new(jpeg), filename: "banner-#{channel.id}.jpg", content_type: "image/jpeg")
    end

    it "puts the banner in the top spot and the avatar in the kv-table (inline) when a banner is attached" do
      attach_avatar
      attach_banner
      node = render_card
      expect(node.at_css(".pito-channel-detail__banner")).to be_present
      expect(node.at_css("img.pito-channel-detail__avatar-inline")).to be_present
      expect(node.text).to include("Avatar")
    end

    it "fills the banner spot with a click-to-sync placeholder (avatar still inline) when there is no banner (item 22)" do
      attach_avatar
      node   = render_card
      banner = node.at_css(".pito-channel-detail__banner")
      expect(banner).to be_present
      fallback = banner.at_css(".pito-image-fallback")
      expect(fallback).to be_present
      expect(fallback["data-pito--chat-prefill-text-value"]).to eq("sync channel #{channel.at_handle}")
      # the attached avatar still renders inline in the kv-table
      expect(node.at_css("img.pito-channel-detail__avatar-inline")).to be_present
    end

    it "shows a circle click-to-sync placeholder for the inline avatar when no avatar is attached (item 22)" do
      node     = render_card
      fallback = node.at_css(".pito-image-fallback.pito-image-fallback--circle.pito-channel-detail__avatar-inline")
      expect(fallback).to be_present
      expect(fallback["data-pito--chat-prefill-text-value"]).to eq("sync channel #{channel.at_handle}")
    end

    it "vertically centers the 'Avatar' kv-label to the avatar image (13.11)" do
      attach_avatar
      node = render_card
      label = node.css("span.self-center").find { |s| s.text.include?(I18n.t("pito.channel.detail.avatar")) }
      expect(label).to be_present
    end
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
