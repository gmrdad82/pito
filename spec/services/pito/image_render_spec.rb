# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ImageRender, type: :component do
  describe ".call" do
    context "when a url is present" do
      let(:url) { "/rails/active_storage/proxy/abc.png" }

      it "returns an ImageTag renderable" do
        result = described_class.call(url: url, shape: :rect, sync_command: "sync vid #1")
        expect(result).to be_a(Pito::ImageRender::ImageTag)
      end

      it "renders an <img> carrying the url, alt, and class" do
        result = described_class.call(
          url: url, shape: :rect, sync_command: "sync vid #1",
          alt: "My vid", html_class: "block pito-cover-pan"
        )
        html = result.render_in(nil)
        expect(html).to include("<img")
        expect(html).to include('src="/rails/active_storage/proxy/abc.png"')
        expect(html).to include('alt="My vid"')
        expect(html).to include("pito-cover-pan")
      end
    end

    context "when the url is nil / blank (nothing attached)" do
      it "returns a Pito::ImageFallbackComponent" do
        result = described_class.call(url: nil, shape: :circle, sync_command: "sync channel @pito")
        expect(result).to be_a(Pito::ImageFallbackComponent)
      end

      it "treats a blank string as no image" do
        result = described_class.call(url: "", shape: :rect, sync_command: "sync vid #1")
        expect(result).to be_a(Pito::ImageFallbackComponent)
      end

      it "passes the host sizing class through to the placeholder" do
        component = described_class.call(
          url: nil, shape: :circle, sync_command: "sync channel @pito",
          fallback_class: "pito-channel-tiny-avatar"
        )
        expect(render_inline(component).at_css(".pito-image-fallback.pito-channel-tiny-avatar")).to be_present
      end
    end
  end
end
