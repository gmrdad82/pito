# frozen_string_literal: true

require "rails_helper"

# FilterComponent is the generic "shortcut + value" pair behind the period
# cycler. Its `shortcut:` is a plain key LABEL — ShortcutComponent runs it
# through Pito::Keybinding::Glyph on the way out, so what renders is the glyph
# form ("ctrl+space"), never the literal string passed in. Asserting the glyph here is
# what keeps +/- separator drift and Esc/esc casing drift from leaking back
# into the UI through this component.
RSpec.describe Pito::Shell::Chatbox::FilterComponent do
  describe "rendered output" do
    it "renders inside an inline-flex gap-2 wrapper" do
      node = render_inline(described_class.new(shortcut: "ctrl+space", value: "@all"))
      wrapper = node.css("span.inline-flex.items-center.gap-2").first
      expect(wrapper).not_to be_nil
    end

    it "renders the shortcut as a kbd-shimmer glyph via ShortcutComponent" do
      node = render_inline(described_class.new(shortcut: "ctrl+space", value: "@all"))
      yellow = node.css("span.pito-kbd-shimmer").first
      expect(yellow).not_to be_nil
      expect(yellow.text).to eq("ctrl+space")
    end

    it "renders the value in a shimmer span" do
      node = render_inline(described_class.new(shortcut: "ctrl+space", value: "7d"))
      shimmer = node.css("span.pito-token").first
      expect(shimmer).not_to be_nil
      expect(shimmer.text).to eq("7d")
    end

    it "renders the shortcut before the value" do
      node = render_inline(described_class.new(shortcut: "ctrl+space", value: "@sports"))
      spans = node.css("span.inline-flex.items-center.gap-2 > span")
      expect(spans.first["class"]).to include("pito-kbd-shimmer")
      expect(spans.last["class"]).to include("pito-token")
    end

    it "renders various shortcut + value combinations in the glyph convention" do
      [
        [ "ctrl+space", "ctrl+space",  "@gaming" ],
        [ "ctrl-space", "ctrl+space",  "30d" ],  # '-' separator normalizes identically
        [ "ctrl+k",     "ctrl+k",  "1h" ],   # letters stay lowercase
        [ "esc",        "Esc", "@all" ]  # named keys stay Title-case WORDS
      ].each do |shortcut, glyph, value|
        node = render_inline(described_class.new(shortcut: shortcut, value: value))
        expect(node.css("span.pito-kbd-shimmer").text).to eq(glyph)
        expect(node.css("span.pito-token").text).to eq(value)
      end
    end

    it "never echoes a retired shift+tab / shift+space label verbatim" do
      node = render_inline(described_class.new(shortcut: "ctrl+space", value: "@all"))
      expect(node.to_html).not_to include("shift+tab")
      expect(node.to_html).not_to include("shift+space")
    end
  end
end
