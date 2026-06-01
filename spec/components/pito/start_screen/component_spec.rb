# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::StartScreen::Component do
  let(:defaults) { { repo_url: "https://github.com/gmrdad82/pito", license_url: "https://www.gnu.org/licenses/agpl-3.0.html" } }

  describe "#initialize" do
    it "accepts repo_url and license_url" do
      expect(described_class.new(**defaults)).to be_a(described_class)
    end
  end

  describe "rendered output" do
    subject(:node) { render_inline(described_class.new(**defaults)) }

    it "renders the ASCII logo" do
      expect(node.css("pre.pito-start-screen__logo")).not_to be_empty
    end

    it "renders the tip prefix translation" do
      expect(node.to_html).to include("Tip")
    end

    it "renders the tip placeholder translation" do
      expect(node.to_html).to include("[placeholder for tip dictionary]")
    end

    it "renders a full-viewport flex container" do
      expect(node.css("div.min-h-screen")).not_to be_empty
    end

    it "does not render a version string" do
      expect(node.to_html).not_to match(/v\d+\.\d+/)
    end
  end

  describe "bottom corner links" do
    subject(:node) { render_inline(described_class.new(**defaults)) }

    it "renders the repo link with the correct label" do
      link = node.css("a[href='https://github.com/gmrdad82/pito']").first
      expect(link).not_to be_nil
      expect(link.text.strip).to eq("GitHub Source")
    end

    it "renders the license link with the correct label" do
      link = node.css("a[href='https://www.gnu.org/licenses/agpl-3.0.html']").first
      expect(link).not_to be_nil
      expect(link.text.strip).to eq("AGPL-3.0")
    end

    it "opens corner links in a new tab" do
      links = node.css("[data-pito--home-transition-target='fadeOut'] a")
      links.each { |a| expect(a["target"]).to eq("_blank") }
    end
  end

  describe "home-transition wiring" do
    subject(:node) { render_inline(described_class.new(**defaults)) }

    it "mounts pito--home-transition on the outer wrapper" do
      expect(node.css("[data-controller='pito--home-transition']")).not_to be_empty
    end

    it "has a chatboxArea target" do
      expect(node.css("[data-pito--home-transition-target='chatboxArea']")).not_to be_empty
    end

    it "has named animation targets for tip and corners" do
      %w[tip corners].each do |target|
        expect(node.css("[data-pito--home-transition-target='#{target}']")).not_to be_empty,
          "expected a #{target} target"
      end
    end

    it "has logoRow targets for the per-row unstable dissolve" do
      rows = node.css("[data-pito--home-transition-target='logoRow']")
      expect(rows.length).to eq(6)
    end

    it "chatboxArea carries the width constraint directly (max-w-600)" do
      chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
      expect(chatbox_area["class"]).to include("max-w-[600px]")
    end

    it "mini-status is inside chatboxArea so it animates as one unit" do
      chatbox_area = node.css("[data-pito--home-transition-target='chatboxArea']").first
      expect(chatbox_area.to_html).to include("MiniStatus").or include("not authenticated")
    end

    it "has a hidden conversationChrome target" do
      chrome = node.css("[data-pito--home-transition-target='conversationChrome']").first
      expect(chrome).not_to be_nil
      expect(chrome["style"]).to include("display:none")
    end
  end
end
