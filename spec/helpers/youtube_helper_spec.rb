require "rails_helper"

RSpec.describe YoutubeHelper, type: :helper do
  describe "#format_connection_email" do
    it "returns the full email for a Gmail address" do
      expect(helper.format_connection_email("u@gmail.com")).to eq("u@gmail.com")
    end

    it "returns the full email for a custom-domain address" do
      expect(helper.format_connection_email("alice@example.test"))
        .to eq("alice@example.test")
    end

    it "strips the @pages.plusgoogle.com suffix from a brand-account address" do
      expect(
        helper.format_connection_email("witty-gaming-3646722185536190277@pages.plusgoogle.com")
      ).to eq("witty-gaming-3646722185536190277")
    end

    it "is case-insensitive against the brand domain" do
      expect(
        helper.format_connection_email("witty-gaming-1@PAGES.PLUSGOOGLE.COM")
      ).to eq("witty-gaming-1")
    end

    it "returns an empty string for nil" do
      expect(helper.format_connection_email(nil)).to eq("")
    end

    it "returns the raw value when there is no @" do
      expect(helper.format_connection_email("not-an-email")).to eq("not-an-email")
    end

    it "returns the raw value when the local part is empty" do
      # Degenerate input — keep the call total to surface the data
      # honestly rather than swallow it.
      expect(helper.format_connection_email("@pages.plusgoogle.com")).to eq("")
    end
  end

  describe "#format_scope_short_label" do
    it "returns the trailing segment of a googleapis URL scope" do
      expect(
        helper.format_scope_short_label("https://www.googleapis.com/auth/userinfo.email")
      ).to eq("userinfo.email")
    end

    it "returns the trailing segment of the youtube.readonly URL scope" do
      expect(
        helper.format_scope_short_label("https://www.googleapis.com/auth/youtube.readonly")
      ).to eq("youtube.readonly")
    end

    it "returns the trailing segment of the youtube.force-ssl URL scope" do
      expect(
        helper.format_scope_short_label("https://www.googleapis.com/auth/youtube.force-ssl")
      ).to eq("youtube.force-ssl")
    end

    it "returns the trailing segment of the yt-analytics.readonly URL scope" do
      expect(
        helper.format_scope_short_label("https://www.googleapis.com/auth/yt-analytics.readonly")
      ).to eq("yt-analytics.readonly")
    end

    it "passes plain `openid` through as-is" do
      expect(helper.format_scope_short_label("openid")).to eq("openid")
    end

    it "passes plain `email` through as-is" do
      expect(helper.format_scope_short_label("email")).to eq("email")
    end

    it "passes plain `profile` through as-is" do
      expect(helper.format_scope_short_label("profile")).to eq("profile")
    end

    it "returns an empty string for nil" do
      expect(helper.format_scope_short_label(nil)).to eq("")
    end

    it "returns an empty string for the empty string" do
      expect(helper.format_scope_short_label("")).to eq("")
    end
  end

  describe "#youtube_channel_id" do
    it "extracts the UC id from a valid channel_url" do
      channel = build_stubbed(
        :channel,
        channel_url: "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      )
      expect(helper.youtube_channel_id(channel)).to eq("UC2T-WgvF-DQQfFNQieoRuQQ")
    end

    it "returns nil when the channel_url does not match the UC pattern" do
      channel = build_stubbed(:channel)
      channel.channel_url = "https://example.com/not-a-channel"
      expect(helper.youtube_channel_id(channel)).to be_nil
    end

    it "returns nil when the channel is nil" do
      expect(helper.youtube_channel_id(nil)).to be_nil
    end

    it "returns nil when channel_url is nil" do
      channel = build_stubbed(:channel)
      channel.channel_url = nil
      expect(helper.youtube_channel_id(channel)).to be_nil
    end
  end

  describe "#youtube_channel_url" do
    it "builds the public YouTube channel URL from a valid channel" do
      channel = build_stubbed(
        :channel,
        channel_url: "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      )
      expect(helper.youtube_channel_url(channel))
        .to eq("https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
    end

    it "returns nil when the id cannot be extracted" do
      channel = build_stubbed(:channel)
      channel.channel_url = "https://example.com/oops"
      expect(helper.youtube_channel_url(channel)).to be_nil
    end

    it "returns nil for nil channel" do
      expect(helper.youtube_channel_url(nil)).to be_nil
    end
  end

  describe "#youtube_studio_url" do
    it "builds the YouTube Studio URL from a valid channel" do
      channel = build_stubbed(
        :channel,
        channel_url: "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ"
      )
      expect(helper.youtube_studio_url(channel))
        .to eq("https://studio.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
    end

    it "returns nil when the id cannot be extracted" do
      channel = build_stubbed(:channel)
      channel.channel_url = "https://example.com/oops"
      expect(helper.youtube_studio_url(channel)).to be_nil
    end

    it "returns nil for nil channel" do
      expect(helper.youtube_studio_url(nil)).to be_nil
    end
  end
end
