require "rails_helper"

RSpec.describe Pito::Theme::Sections do
  describe "BG constant" do
    it "covers every section the layout can render (8 sections)" do
      expect(described_class::BG.keys).to match_array(%w[
        home channels videos games projects settings notifications calendar
      ])
    end

    it "locks settings bg to the user-picked #34333b" do
      expect(described_class::BG.fetch("settings")).to eq("#34333b")
    end

    it "freezes the BG hash so callers can't mutate the source of truth" do
      expect(described_class::BG).to be_frozen
    end

    it "aliases videos to the channels bg" do
      expect(described_class::BG.fetch("videos")).to eq(described_class::BG.fetch("channels"))
    end

    it "aliases projects to the games bg" do
      expect(described_class::BG.fetch("projects")).to eq(described_class::BG.fetch("games"))
    end
  end

  describe "ACCENT constant" do
    it "covers every section the layout can render (8 sections)" do
      expect(described_class::ACCENT.keys).to match_array(%w[
        home channels videos games projects settings notifications calendar
      ])
    end

    it "freezes the ACCENT hash" do
      expect(described_class::ACCENT).to be_frozen
    end

    it "matches the Dracula L2 tokens declared in application.css" do
      # These four atoms anchor the section-accent cascade. Drift here
      # means the inline body style disagrees with any consumer still
      # reading the CSS `--section-accent-*` atoms — keep them in sync.
      expect(described_class::ACCENT.fetch("home")).to     eq("#bd93f9") # dracula-purple
      expect(described_class::ACCENT.fetch("channels")).to eq("#ff5555") # dracula-red
      expect(described_class::ACCENT.fetch("games")).to    eq("#7eb6ff") # pale-cobalt
      expect(described_class::ACCENT.fetch("settings")).to eq("#ffb86c") # dracula-orange
    end

    it "aliases videos to the channels accent" do
      expect(described_class::ACCENT.fetch("videos")).to eq(described_class::ACCENT.fetch("channels"))
    end

    it "aliases projects to the games accent" do
      expect(described_class::ACCENT.fetch("projects")).to eq(described_class::ACCENT.fetch("games"))
    end

    it "folds notifications + calendar into the home (purple) family" do
      expect(described_class::ACCENT.fetch("notifications")).to eq(described_class::ACCENT.fetch("home"))
      expect(described_class::ACCENT.fetch("calendar")).to      eq(described_class::ACCENT.fetch("home"))
    end
  end

  describe ".bg" do
    it "returns the locked settings bg" do
      expect(described_class.bg("settings")).to eq("#34333b")
    end

    it "looks the section key up via to_s so symbol callers also work" do
      expect(described_class.bg(:games)).to eq(described_class::BG.fetch("games"))
    end

    it "falls back to DEFAULT_BG (#282a36 — Dracula raw bg) for unknown sections" do
      expect(described_class.bg("nope")).to eq(described_class::DEFAULT_BG)
      expect(described_class::DEFAULT_BG).to eq("#282a36")
    end

    it "falls back to DEFAULT_BG when section is nil" do
      expect(described_class.bg(nil)).to eq(described_class::DEFAULT_BG)
    end
  end

  describe ".accent" do
    it "returns Dracula orange for settings" do
      expect(described_class.accent("settings")).to eq("#ffb86c")
    end

    it "returns Dracula red for channels and videos" do
      expect(described_class.accent("channels")).to eq("#ff5555")
      expect(described_class.accent("videos")).to   eq("#ff5555")
    end

    it "returns pale cobalt for games and projects" do
      expect(described_class.accent("games")).to    eq("#7eb6ff")
      expect(described_class.accent("projects")).to eq("#7eb6ff")
    end

    it "returns Dracula purple for home / notifications / calendar" do
      expect(described_class.accent("home")).to          eq("#bd93f9")
      expect(described_class.accent("notifications")).to eq("#bd93f9")
      expect(described_class.accent("calendar")).to      eq("#bd93f9")
    end

    it "falls back to DEFAULT_ACCENT (#bd93f9 — Dracula purple) for unknown sections" do
      expect(described_class.accent("nope")).to eq(described_class::DEFAULT_ACCENT)
      expect(described_class::DEFAULT_ACCENT).to eq("#bd93f9")
    end

    it "falls back to DEFAULT_ACCENT when section is nil" do
      expect(described_class.accent(nil)).to eq(described_class::DEFAULT_ACCENT)
    end
  end

  describe ".mix" do
    it "computes a 4% accent wash matching the pre-refactor color-mix math" do
      # Hand-computed: each channel is bg + (accent - bg) * 0.04, rounded.
      # accent #ffb86c -> (255, 184, 108)
      # bg     #282a36 -> ( 40,  42,  54)
      # r = 40 + (255-40)*0.04 = 48.6 -> 49 -> 0x31
      # g = 42 + (184-42)*0.04 = 47.68 -> 48 -> 0x30
      # b = 54 + (108-54)*0.04 = 56.16 -> 56 -> 0x38
      expect(described_class.mix("#ffb86c", 4, "#282a36")).to eq("#313038")
    end

    it "returns the bg unchanged at 0% (pure bg)" do
      expect(described_class.mix("#ff5555", 0, "#34333b")).to eq("#34333b")
    end

    it "returns the accent unchanged at 100% (pure accent)" do
      expect(described_class.mix("#ff5555", 100, "#34333b")).to eq("#ff5555")
    end

    it "is linear: 50% sits halfway between bg and accent components" do
      # bg #000000 -> (0, 0, 0); accent #ffffff -> (255, 255, 255)
      # 50% -> (127.5, 127.5, 127.5) -> rounds to 128 -> #808080
      expect(described_class.mix("#ffffff", 50, "#000000")).to eq("#808080")
    end

    it "tolerates upper-case hex input" do
      expect(described_class.mix("#FFB86C", 4, "#282A36")).to eq("#313038")
    end

    it "raises ArgumentError on a negative percent" do
      expect { described_class.mix("#ffffff", -1, "#000000") }.to raise_error(ArgumentError, /0-100/)
    end

    it "raises ArgumentError on a percent over 100" do
      expect { described_class.mix("#ffffff", 101, "#000000") }.to raise_error(ArgumentError, /0-100/)
    end
  end

  describe ".section_border" do
    it "computes the 35% accent + section bg for settings (mirrors --color-section-border)" do
      # accent #ffb86c -> (255, 184, 108)
      # bg     #34333b -> ( 52,  51,  59)
      # r = 52 + (255-52)*0.35 = 123.05 -> 123 -> 0x7b
      # g = 51 + (184-51)*0.35 = 97.55  -> 98  -> 0x62
      # b = 59 + (108-59)*0.35 = 76.15  -> 76  -> 0x4c
      expect(described_class.section_border("settings")).to eq("#7b624c")
    end

    it "returns the DEFAULT_ACCENT-vs-DEFAULT_BG border for unknown sections" do
      # accent #bd93f9 -> (189, 147, 249); bg #282a36 -> (40, 42, 54)
      # r = 40 + (189-40)*0.35 = 92.15 -> 92  -> 0x5c
      # g = 42 + (147-42)*0.35 = 78.75 -> 79  -> 0x4f
      # b = 54 + (249-54)*0.35 = 122.25 -> 122 -> 0x7a
      expect(described_class.section_border("nope")).to eq("#5c4f7a")
    end
  end

  describe ".hex_to_rgb / .rgb_to_hex" do
    it "round-trips a known hex losslessly" do
      r, g, b = described_class.hex_to_rgb("#ffb86c")
      expect([ r, g, b ]).to eq([ 255, 184, 108 ])
      expect(described_class.rgb_to_hex(r, g, b)).to eq("#ffb86c")
    end

    it "accepts hex without a leading #" do
      expect(described_class.hex_to_rgb("282a36")).to eq([ 40, 42, 54 ])
    end

    it "lowercases the output hex" do
      expect(described_class.rgb_to_hex(255, 184, 108)).to eq("#ffb86c")
    end

    it "pads single-digit channels with a leading zero" do
      expect(described_class.rgb_to_hex(1, 2, 3)).to eq("#010203")
    end
  end
end
