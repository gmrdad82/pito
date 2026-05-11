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
end
