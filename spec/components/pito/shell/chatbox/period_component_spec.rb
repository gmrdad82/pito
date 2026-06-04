# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::Chatbox::PeriodComponent do
  describe "label text" do
    it "renders the i18n label 'Period' (capitalized)" do
      node = render_inline(described_class.new(period: "7d"))
      expect(node.to_html).to include("Period")
    end

    it "renders the label in a muted span" do
      node = render_inline(described_class.new(period: "7d"))
      faded = node.css("span.text-fg-faded").first
      expect(faded).not_to be_nil
      expect(faded.text).to include("Period")
    end
  end

  describe "period value" do
    it "renders the period value in a span.text-cyan" do
      node = render_inline(described_class.new(period: "7d"))
      cyan_texts = node.css("span.text-cyan").map(&:text)
      expect(cyan_texts).to include("7d")
    end

    it "uses tight gap-1 spacing (inline-flex wrapper) instead of ml-2" do
      node = render_inline(described_class.new(period: "7d"))
      wrapper = node.css("span.inline-flex.items-center.gap-1").first
      expect(wrapper).not_to be_nil
      cyan_span = wrapper.css("span.text-cyan").first
      expect(cyan_span).not_to be_nil
      expect(cyan_span["class"]).not_to include("ml-2")
    end
  end

  describe "shift+space shortcut" do
    it "renders the shift+space shortcut in bold yellow" do
      node = render_inline(described_class.new(period: "7d"))
      yellow = node.css("span.font-bold.text-yellow").first
      expect(yellow).not_to be_nil
      expect(yellow.text).to include("shift+space")
    end
  end

  describe "various period strings" do
    [ [ "7d", "7d" ], [ "30d", "30d" ], [ "1h", "1h" ] ].each do |period, expected|
      it "renders '#{expected}' correctly" do
        node = render_inline(described_class.new(period: period))
        expect(node.css("span.text-cyan").map(&:text)).to include(expected)
      end
    end
  end
end
