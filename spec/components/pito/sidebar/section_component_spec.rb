# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::SectionComponent do
  describe "#initialize" do
    it "accepts a title_key" do
      comp = described_class.new(title_key: "pito.sidebar.section.overview")
      expect(comp).to be_a(described_class)
    end
  end

  describe "rendered output" do
    it "renders the translated section title" do
      node = render_inline(described_class.new(title_key: "pito.sidebar.section.overview"))
      # pito.sidebar.section.overview => "Overview"
      expect(node.to_html).to include("Overview")
    end

    it "renders the top-level wrapper div" do
      node = render_inline(described_class.new(title_key: "pito.sidebar.section.overview"))
      expect(node.css("div")).not_to be_empty
    end
  end

  describe "body slot" do
    it "renders body slot content" do
      node = render_inline(
        described_class.new(title_key: "pito.sidebar.section.overview")
      ) do |c|
        c.with_body { "section body text" }
      end
      expect(node.to_html).to include("section body text")
    end

    it "renders without body slot content" do
      node = render_inline(described_class.new(title_key: "pito.sidebar.section.channels"))
      # pito.sidebar.section.channels => "Channels covering this game"
      expect(node.to_html).to include("Channels covering this game")
    end
  end

  describe "all known section keys" do
    {
      "pito.sidebar.section.overview"       => "Overview",
      "pito.sidebar.section.channels"       => "Channels covering this game",
      "pito.sidebar.section.top_videos"     => "Top videos",
      "pito.sidebar.section.tags"           => "Tags",
      "pito.sidebar.section.recommendation" => "Recommendation",
      "pito.sidebar.section.quick_commands" => "Quick commands"
    }.each do |key, expected_text|
      it "translates #{key} correctly" do
        node = render_inline(described_class.new(title_key: key))
        expect(node.to_html).to include(expected_text)
      end
    end
  end
end
