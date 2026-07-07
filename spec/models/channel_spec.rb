# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel, type: :model do
  describe "#at_handle" do
    it "returns the handle unchanged when it already has a leading @" do
      channel = build(:channel, handle: "@foo")
      expect(channel.at_handle).to eq("@foo")
    end

    it "adds a leading @ when the handle is stored without one" do
      channel = build(:channel, handle: "bar")
      expect(channel.at_handle).to eq("@bar")
    end

    it "never double-prefixes a handle stored as @@something" do
      channel = build(:channel, handle: "@@oops")
      expect(channel.at_handle).to eq("@oops")
    end

    it "handles nil handle gracefully" do
      channel = build(:channel, handle: nil)
      expect(channel.at_handle).to eq("@")
    end
  end

  describe ".resolve_handle (#7 — exact then pg_trgm fuzzy)" do
    let!(:channel) { create(:channel, handle: "@fighterpro", title: "Fighter Pro") }

    it "resolves an exact @handle" do
      expect(described_class.resolve_handle("@fighterpro")).to eq(channel)
    end

    it "resolves @-agnostically (no leading @)" do
      expect(described_class.resolve_handle("fighterpro")).to eq(channel)
    end

    it "resolves case-insensitively" do
      expect(described_class.resolve_handle("FIGHTERPRO")).to eq(channel)
    end

    it "fuzzy-resolves a partial handle (fighter → @fighterpro)" do
      expect(described_class.resolve_handle("fighter")).to eq(channel)
    end

    it "fuzzy-resolves a typo'd handle" do
      expect(described_class.resolve_handle("fihgterpro")).to eq(channel)
    end

    it "returns nil for a below-threshold non-match" do
      expect(described_class.resolve_handle("zzzzzz")).to be_nil
    end

    it "returns nil for blank input" do
      expect(described_class.resolve_handle("")).to be_nil
      expect(described_class.resolve_handle("@")).to be_nil
    end

    it "prefers an exact match over a fuzzy neighbour" do
      exact = create(:channel, handle: "@fighter", title: "Fighter")
      expect(described_class.resolve_handle("fighter")).to eq(exact)
    end
  end

  describe "#youtube_channel_url" do
    it "returns the @handle form URL when handle is present" do
      channel = build(:channel, handle: "@gmrdad82", youtube_channel_id: "UCtest")
      expect(channel.youtube_channel_url).to eq("https://www.youtube.com/@gmrdad82")
    end

    it "strips a leading @ before building the URL" do
      channel = build(:channel, handle: "gmrdad82", youtube_channel_id: "UCtest")
      expect(channel.youtube_channel_url).to eq("https://www.youtube.com/@gmrdad82")
    end

    it "returns the /channel/<id> form when handle is blank" do
      channel = build(:channel, handle: nil, youtube_channel_id: "UCabc123")
      expect(channel.youtube_channel_url).to eq("https://www.youtube.com/channel/UCabc123")
    end
  end

  describe "#youtube_studio_url" do
    it "returns the Studio URL using youtube_channel_id" do
      channel = build(:channel, youtube_channel_id: "UCxyz999")
      expect(channel.youtube_studio_url).to eq("https://studio.youtube.com/channel/UCxyz999")
    end
  end

  describe "#banner" do
    let(:channel) { create(:channel) }
    # Raw bytes — not a processed image; the master stores whatever the CDN returned.
    let(:raw_bytes) { "fake-banner-raw-master" }

    it "is an ActiveStorage attachment, unattached by default" do
      expect(channel.banner).not_to be_attached
    end

    it "declares a :display named variant (450×253)" do
      reflection = Channel.attachment_reflections["banner"]
      expect(reflection.named_variants).to have_key(:display)
    end

    it "#banner_url is nil when no banner is attached" do
      expect(channel.banner_url).to be_nil
    end

    it "#banner_url returns a host-less proxy path once a banner is attached" do
      channel.banner.attach(io: StringIO.new(raw_bytes), filename: "banner-#{channel.id}.jpg", content_type: "image/jpeg")
      url = channel.banner_url
      expect(url).to be_present
      expect(url).to start_with("/") # host-less (loads from whatever host serves the page)
    end
  end

  describe "#avatar" do
    let(:channel)   { create(:channel) }
    let(:raw_bytes) { "fake-avatar-raw-master" }

    def attach_avatar
      channel.avatar.attach(io: StringIO.new(raw_bytes), filename: "avatar-#{channel.id}.jpg", content_type: "image/jpeg")
    end

    it "declares the :sm (60×60) and :xs (35×35) named variants (:lg retired with the card form)" do
      reflection = Channel.attachment_reflections["avatar"]
      expect(reflection.named_variants).to have_key(:sm)
      expect(reflection.named_variants).to have_key(:xs)
      expect(reflection.named_variants).not_to have_key(:lg)
    end

    it "#avatar_inline_url is nil when no avatar is attached" do
      expect(channel.avatar_inline_url).to be_nil
    end

    it "#avatar_inline_url returns a host-less proxy path once an avatar is attached" do
      attach_avatar
      url = channel.avatar_inline_url
      expect(url).to be_present
      expect(url).to start_with("/")
    end
  end

  # ── #like_count (G26.2 / G28 / G30) ──────────────────────────────────────────
  #
  # YouTube exposes no channel-level like counter — the channel's likes are
  # MATERIALIZED into its own Pito::Stats row by Channel::StatsRefresh; the
  # reader never live-sums videos at render, and coalesces nil to 0 (G30).

  describe "#like_count" do
    let(:channel) { create(:channel) }

    it "reads the materialized likes row" do
      Pito::Stats.set(channel, :likes, 155)
      expect(channel.like_count).to eq(155)
    end

    it "is 0 before the first rollup (nil coalesces — G30)" do
      expect(channel.like_count).to eq(0)
    end

    it "does not live-sum: video likes don't show until StatsRefresh runs" do
      video = create(:video, channel: channel)
      Pito::Stats.set(video, :likes, 100)
      expect(channel.like_count).to eq(0)

      Channel::StatsRefresh.call(channel)
      expect(channel.like_count).to eq(100)
    end
  end
end
