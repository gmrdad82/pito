# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::GetAppBannerComponent, type: :component do
  ANDROID_BROWSER_UA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/126.0"
  NATIVE_SHELL_UA    = "Mozilla/5.0 (Linux; Android 14; Pixel 8) Hotwire Native Android"
  DESKTOP_UA         = "Mozilla/5.0 (X11; Linux x86_64) Firefox/128.0"

  context "for an Android browser visitor" do
    let(:fragment) { render_inline(described_class.new(user_agent: ANDROID_BROWSER_UA)) }

    it "renders the banner" do
      expect(fragment.css("[data-controller='pito--app-banner']")).not_to be_empty
    end

    it "ships hidden until the Stimulus controller reveals it" do
      root = fragment.css("[data-controller='pito--app-banner']").first
      expect(root["class"]).to include("hidden")
    end

    it "is as wide as the conversation column, not the page" do
      expect(fragment.css(".pito-conversation-col")).not_to be_empty
    end

    it "links to the latest APK release asset" do
      href = fragment.css("a").first["href"]
      expect(href).to eq("https://github.com/gmrdad82/pito-android/releases/latest/download/pito.apk")
    end

    it "wears the gold shiny material via the generic chip component" do
      chip = fragment.css(".pito-shiny.pito-get-app").first
      expect(chip).not_to be_nil
      expect(chip["data-material"]).to eq("gold")
      expect(fragment.css("a").first["class"]).to include("pito-get-app__cta")
    end

    it "floats below the top edge instead of gluing to it" do
      root = fragment.css("[data-controller='pito--app-banner']").first
      expect(root["class"]).to include("top-3")
    end

    it "offers a dismiss action" do
      button = fragment.css("button[data-action='pito--app-banner#dismiss']").first
      expect(button.text).to eq("[x]")
    end
  end

  context "inside the Hotwire Native shell" do
    it "does not render — never advertise the app inside the app" do
      fragment = render_inline(described_class.new(user_agent: NATIVE_SHELL_UA))
      expect(fragment.to_html).to be_empty
    end
  end

  context "for a non-Android visitor" do
    it "does not render" do
      fragment = render_inline(described_class.new(user_agent: DESKTOP_UA))
      expect(fragment.to_html).to be_empty
    end
  end

  context "with no User-Agent at all" do
    it "does not render" do
      fragment = render_inline(described_class.new(user_agent: nil))
      expect(fragment.to_html).to be_empty
    end
  end
end
