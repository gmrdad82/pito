# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::Component do
  describe "#initialize" do
    it "accepts required title and subtitle_key" do
      comp = described_class.new(title: "Hollow Knight", subtitle_key: "pito.sidebar.esc_hint")
      expect(comp).to be_a(described_class)
    end

    it "accepts optional subtitle_args" do
      comp = described_class.new(
        title: "Hollow Knight",
        subtitle_key: "pito.sidebar.game.subtitle",
        subtitle_args: { date: "2024-01-01" }
      )
      expect(comp).to be_a(described_class)
    end
  end

  describe "rendered output" do
    subject(:node) do
      render_inline(
        described_class.new(
          title: "Hollow Knight",
          subtitle_key: "pito.sidebar.esc_hint"
        )
      )
    end

    it "renders the title" do
      expect(node.to_html).to include("Hollow Knight")
    end

    it "renders the translated esc_hint subtitle" do
      # pito.sidebar.esc_hint => "Esc"
      expect(node.to_html).to include("Esc")
    end

    it "renders an aside element" do
      expect(node.css("aside")).not_to be_empty
    end
  end

  describe "subtitle with interpolation" do
    it "renders the interpolated subtitle" do
      node = render_inline(
        described_class.new(
          title: "My Game",
          subtitle_key: "pito.sidebar.game.subtitle",
          subtitle_args: { date: "Jan 1 2024" }
        )
      )
      # pito.sidebar.game.subtitle => "Game · imported %{date}"
      expect(node.to_html).to include("Game")
      expect(node.to_html).to include("Jan 1 2024")
    end
  end

  describe "subtitle slot (rich subtitle overrides subtitle_key)" do
    it "renders custom subtitle slot content" do
      node = render_inline(
        described_class.new(
          title:        "Game",
          subtitle_key: "pito.sidebar.game.subtitle",
          subtitle_args: { date: "Jan 1" }
        )
      ) do |c|
        c.with_subtitle { "custom rich subtitle" }
      end
      expect(node.to_html).to include("custom rich subtitle")
    end

    it "does NOT render the subtitle_key translation when a subtitle slot is provided" do
      node = render_inline(
        described_class.new(
          title:        "Game",
          subtitle_key: "pito.sidebar.game.subtitle",
          subtitle_args: { date: "Jan 1" }
        )
      ) do |c|
        c.with_subtitle { "custom rich subtitle" }
      end
      # subtitle_key would produce "Game · imported Jan 1" — that text must be absent
      expect(node.to_html).not_to include("imported Jan 1")
    end

    it "renders without a subtitle when neither subtitle slot nor subtitle_key is given" do
      node = render_inline(described_class.new(title: "Game"))
      # No subtitle div with text should appear (only the always-present esc hint span)
      subtitle_divs = node.css("div.text-fg-dim")
      expect(subtitle_divs).to be_empty
    end
  end

  describe "body slot" do
    it "renders body slot content when provided" do
      node = render_inline(described_class.new(title: "Game", subtitle_key: "pito.sidebar.esc_hint")) do |c|
        c.with_body { "body content here" }
      end
      expect(node.to_html).to include("body content here")
    end

    it "renders without body slot" do
      node = render_inline(
        described_class.new(title: "Game", subtitle_key: "pito.sidebar.esc_hint")
      )
      expect(node.css("aside")).not_to be_empty
    end
  end
end
