require "rails_helper"

RSpec.describe "channels/_banner.html.erb", type: :view do
  let(:channel) { build_stubbed(:channel) }

  context "when banner_url is present" do
    before { channel.banner_url = "https://example.test/banner.jpg" }

    it "renders an <img> with the banner_url as src" do
      render "channels/banner", channel: channel
      expect(rendered).to include('<img')
      expect(rendered).to include('src="https://example.test/banner.jpg"')
    end

    it "renders inside a .channel-banner wrapper" do
      render "channels/banner", channel: channel
      expect(rendered).to include('class="channel-banner"')
    end
  end

  context "when banner_url is nil" do
    before { channel.banner_url = nil }

    it "renders nothing (the row is hidden entirely per locked decision)" do
      render "channels/banner", channel: channel
      expect(rendered.strip).to eq("")
    end

    it "does NOT render a placeholder image or block" do
      render "channels/banner", channel: channel
      expect(rendered).not_to include("<img")
      expect(rendered).not_to include("no banner")
    end
  end

  context "when banner_url is the empty string" do
    before { channel.banner_url = "" }

    it "is treated like nil (hidden row)" do
      render "channels/banner", channel: channel
      expect(rendered.strip).to eq("")
    end
  end
end
