# frozen_string_literal: true

require "rails_helper"

# Table-driven parity with pito-tui's TestKeyGlyph (internal/ui/render/keyglyph_test.go)
# — the web and terminal glyph formatters must agree pixel-for-glyph.
RSpec.describe Pito::Keybinding::Glyph do
  describe ".format" do
    {
      # Modifier + named key.
      "ctrl+space" => "ctrl+space",
      "ctrl+c"     => "ctrl+c",
      "ctrl-c"     => "ctrl+c", # '+' and '-' separators are equivalent
      "ctrl+k"     => "ctrl+k",
      "ctrl+/"     => "ctrl+/",

      # Modifier + "/"-joined pair, sharing the leading modifier.
      "ctrl+u/d" => "ctrl+u/d",
      "ctrl-d/u" => "ctrl+d/u",
      "ctrl+u"   => "ctrl+u",
      "ctrl+d"   => "ctrl+d",

      # Terminal-safety fallback letters stay lowercase even under a modifier.
      "ctrl+f" => "ctrl+f",
      "ctrl+x" => "ctrl+x",

      # Modifier + named key that stays a word.
      "ctrl+home" => "ctrl+Home",
      "ctrl+end"  => "ctrl+End",

      # T8 FULL REVERSAL (2026-07-25, in two stages): shift became the word
      # "shift+" first, then ctrl followed — "then lets revert the and use
      # ctrl+r and so on". Only the arrows stay glyphs.
      "shift+r"       => "shift+r",
      "shift-r"       => "shift+r", # '+' and '-' separators are equivalent
      "shift+tab"     => "shift+tab",
      "shift+up/down" => "shift+↑/↓",
      "shift+↑/↓"     => "shift+↑/↓",
      "shift-↑/↓"     => "shift+↑/↓",
      "shift+up"      => "shift+↑",
      "shift+down"    => "shift+↓",
      "SHIFT+R"       => "shift+r", # case-insensitive modifier word

      # Bare named keys / pairs, no modifier.
      "pgup/pgdn" => "PgUp/PgDn",
      "pgup"      => "PgUp",
      "pgdown"    => "PgDn",
      "esc"       => "Esc",
      "Esc"       => "Esc",
      "enter"     => "Enter",
      "tab"       => "tab",
      "space"     => "space",

      # Bare letters / pairs with no modifier: unambiguous, stay as-is.
      "↑/↓" => "↑/↓",
      "j/k" => "j/k",
      "n"   => "n",
      "dd"  => "dd",
      "a"   => "a",

      # Not keypresses at all: passthrough unchanged.
      "1-9"            => "1-9",
      "1/2/3"          => "1/2/3",
      "/notifications" => "/notifications",
      "?"              => "?",
      "any key"        => "any key",
      ""               => "",

      # Idempotency is covered by the modifier rows above: "ctrl+space" and
      # "shift+tab" are now both input AND output, so those entries assert
      # the round-trip already.
      #
      # Legacy glyph input (pre-reversal): "⌃", "⇧", "␣" and "⇥" degrade
      # gracefully to the spelled-out words rather than round-tripping
      # unchanged — this module no longer emits them, but a caller still
      # holding one should get the current convention back, not a mangled
      # string. Only the arrows still round-trip as themselves.
      "⇧↑/↓" => "shift+↑/↓",
      "⇧r"   => "shift+r",
      "⌃␣"   => "ctrl+space",
      "⌃c"   => "ctrl+c",
      "⌃u/d" => "ctrl+u/d",
      "⌃f"   => "ctrl+f",
      "␣"    => "space",
      "⇥"    => "tab",

      "Home"        => "Home",
      "PgUp/PgDn"   => "PgUp/PgDn",
      "return"      => "Enter",
      "q"           => "q",
      "ctrl+q"      => "ctrl+q",
      "ctrl+s"      => "ctrl+s",
      "left/right"  => "←/→",
      "ctrl+left/right" => "ctrl+←/→",
      "pito"        => "pito", # product word, not a chord: passthrough
      "F1"          => "F1"    # unrecognized chord shape: passthrough
    }.each do |input, expected|
      it "formats #{input.inspect} as #{expected.inspect}" do
        expect(described_class.format(input)).to eq(expected)
      end
    end

    it "accepts a non-string value via to_s" do
      expect(described_class.format(:esc)).to eq("Esc")
    end
  end

  it "is pure: calling repeatedly with the same input always yields the same output" do
    inputs = [ "ctrl+c", "shift+up/down", "esc", "any key", "" ]
    inputs.each do |input|
      first = described_class.format(input)
      5.times { expect(described_class.format(input)).to eq(first) }
    end
  end
end
