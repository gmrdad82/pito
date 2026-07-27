# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::Chatbox::PeriodComponent do
  describe "no 'Period' label word" do
    it "does NOT render the word 'Period' (removed in new design)" do
      node = render_inline(described_class.new(period: "7d"))
      expect(node.to_html).not_to include("Period")
    end
  end

  describe "period value" do
    it "renders the period value in a shimmer span" do
      node = render_inline(described_class.new(period: "7d"))
      shimmer_texts = node.css("span.pito-token").map(&:text)
      expect(shimmer_texts).to include("7d")
    end

    it "uses gap-2 spacing (inline-flex wrapper) instead of ml-2" do
      node = render_inline(described_class.new(period: "7d"))
      wrapper = node.css("span.inline-flex.items-center.gap-2").first
      expect(wrapper).not_to be_nil
      shimmer_span = wrapper.css("span.pito-token").first
      expect(shimmer_span).not_to be_nil
      expect(shimmer_span["class"]).not_to include("ml-2")
    end
  end

  # The period cycler binds ctrl+space (owner 2026-07-24: shift+space retired,
  # both cyclers unified on one physical key), displayed in the glyph
  # convention via Pito::Keybinding::Glyph inside ShortcutComponent — so this
  # renders the SAME token the channel cycler does.
  describe "ctrl+space shortcut (the label)" do
    it "renders the ctrl+space shortcut as a kbd-shimmer glyph token" do
      node = render_inline(described_class.new(period: "7d"))
      kbd = node.css("span.pito-kbd-shimmer").first
      expect(kbd).not_to be_nil
      expect(kbd.text).to eq("ctrl+space")
    end

    it "renders the shortcut before the period value (shortcut is the label)" do
      node = render_inline(described_class.new(period: "7d"))
      spans = node.css("span.inline-flex.items-center.gap-2 > span")
      first_span = spans.first
      expect(first_span["class"]).to include("pito-kbd-shimmer")
      expect(first_span.text).to eq("ctrl+space")
    end

    it "never renders the retired shift+space label" do
      node = render_inline(described_class.new(period: "7d"))
      expect(node.to_html).not_to include("shift+space")
    end
  end

  describe "various period strings" do
    [ [ "7d", "7d" ], [ "30d", "30d" ], [ "1h", "1h" ] ].each do |period, expected|
      it "renders '#{expected}' correctly" do
        node = render_inline(described_class.new(period: period))
        expect(node.css("span.pito-token").map(&:text)).to include(expected)
      end
    end
  end
end
