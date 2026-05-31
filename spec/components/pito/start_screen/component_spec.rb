# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::StartScreen::Component do
  describe "#initialize" do
    it "accepts version" do
      comp = described_class.new(version: "1.0.0")
      expect(comp).to be_a(described_class)
    end

    it "accepts version and marketing_url" do
      comp = described_class.new(version: "1.0.0", marketing_url: "https://example.com")
      expect(comp).to be_a(described_class)
    end
  end

  describe "rendered output" do
    subject(:node) { render_inline(described_class.new(version: "1.2.3")) }

    it "renders the version string" do
      expect(node.to_html).to include("v1.2.3")
    end

    it "renders the tip prefix translation" do
      # pito.start_screen.tip_prefix => "Tip"
      expect(node.to_html).to include("Tip")
    end

    it "renders the tip placeholder translation" do
      # pito.start_screen.tip_placeholder => "[placeholder for tip dictionary]"
      expect(node.to_html).to include("[placeholder for tip dictionary]")
    end

    it "renders the PITO ASCII logo text characters" do
      # The pre block always contains these unicode box-drawing characters
      expect(node.css("pre")).not_to be_empty
    end

    it "renders a full-viewport flex container" do
      outer = node.css("div[style*='min-height: 100vh']").first
      expect(outer).not_to be_nil
    end
  end

  describe "marketing_url" do
    context "when marketing_url is provided" do
      it "renders a link with the host as text" do
        node = render_inline(described_class.new(version: "1.0.0", marketing_url: "https://pito.app"))
        link = node.css("a[href='https://pito.app']").first
        expect(link).not_to be_nil
        expect(link.text).to include("pito.app")
      end

      it "opens in a new tab" do
        node = render_inline(described_class.new(version: "1.0.0", marketing_url: "https://pito.app"))
        link = node.css("a[href='https://pito.app']").first
        expect(link["target"]).to eq("_blank")
      end
    end

    context "when marketing_url is nil" do
      it "does not render a link" do
        node = render_inline(described_class.new(version: "1.0.0", marketing_url: nil))
        expect(node.css("a")).to be_empty
      end
    end

    context "when marketing_url is blank string" do
      it "does not render a link" do
        node = render_inline(described_class.new(version: "1.0.0", marketing_url: ""))
        expect(node.css("a")).to be_empty
      end
    end
  end

  describe "version display" do
    it "prefixes with v" do
      node = render_inline(described_class.new(version: "2.5.1"))
      expect(node.to_html).to include("v2.5.1")
    end
  end
end
