require "rails_helper"

RSpec.describe Pito::Theme do
  describe "DRACULA constant" do
    it "exposes the 11 canonical Dracula atoms" do
      expect(described_class::DRACULA.keys).to match_array(%i[
        bg current_line fg comment cyan green orange pink purple red yellow
      ])
    end

    it "freezes the atom hash" do
      expect(described_class::DRACULA).to be_frozen
    end

    it "locks the core atoms to their Dracula hex values" do
      expect(described_class::DRACULA.fetch(:bg)).to     eq("#282a36")
      expect(described_class::DRACULA.fetch(:fg)).to     eq("#f8f8f2")
      expect(described_class::DRACULA.fetch(:purple)).to eq("#bd93f9")
      expect(described_class::DRACULA.fetch(:red)).to    eq("#ff5555")
      expect(described_class::DRACULA.fetch(:green)).to  eq("#50fa7b")
      expect(described_class::DRACULA.fetch(:pink)).to   eq("#ff79c6")
      expect(described_class::DRACULA.fetch(:orange)).to eq("#ffb86c")
      expect(described_class::DRACULA.fetch(:cyan)).to   eq("#8be9fd")
      expect(described_class::DRACULA.fetch(:yellow)).to eq("#f1fa8c")
      expect(described_class::DRACULA.fetch(:comment)).to      eq("#6272a4")
      expect(described_class::DRACULA.fetch(:current_line)).to eq("#44475a")
    end
  end

  describe "PALE_COBALT" do
    it "exposes the derived /games + /projects accent atom" do
      expect(described_class::PALE_COBALT).to eq("#7eb6ff")
    end
  end

  describe "SECTION_ACCENTS" do
    it "covers every section the layout can render (8 sections)" do
      expect(described_class::SECTION_ACCENTS.keys).to match_array(%w[
        home channels videos games projects settings notifications calendar
      ])
    end

    it "freezes the hash" do
      expect(described_class::SECTION_ACCENTS).to be_frozen
    end

    it "maps the four anchor sections to their locked accents" do
      expect(described_class::SECTION_ACCENTS.fetch("home")).to     eq(described_class::DRACULA.fetch(:purple))
      expect(described_class::SECTION_ACCENTS.fetch("channels")).to eq(described_class::DRACULA.fetch(:red))
      expect(described_class::SECTION_ACCENTS.fetch("games")).to    eq(described_class::PALE_COBALT)
      expect(described_class::SECTION_ACCENTS.fetch("settings")).to eq(described_class::DRACULA.fetch(:orange))
    end

    it "agrees with Pito::Theme::Sections::ACCENT for every section" do
      described_class::SECTION_ACCENTS.each do |section, hex|
        expect(Pito::Theme::Sections::ACCENT.fetch(section)).to eq(hex), "section=#{section}"
      end
    end
  end

  describe "SECTION_BGS" do
    it "covers every section the layout can render" do
      expect(described_class::SECTION_BGS.keys).to match_array(%w[
        home channels videos games projects settings notifications calendar
      ])
    end

    it "freezes the hash" do
      expect(described_class::SECTION_BGS).to be_frozen
    end

    it "locks the user-picked settings bg to #34333b" do
      expect(described_class::SECTION_BGS.fetch("settings")).to eq("#34333b")
    end

    it "agrees with Pito::Theme::Sections::BG for every section" do
      described_class::SECTION_BGS.each do |section, hex|
        expect(Pito::Theme::Sections::BG.fetch(section)).to eq(hex), "section=#{section}"
      end
    end
  end

  describe "SEMANTIC" do
    it "exposes the canonical semantic tokens" do
      expect(described_class::SEMANTIC.keys).to include(
        "color-bg", "color-text", "color-muted", "color-border",
        "color-danger", "color-success", "color-warn", "color-link",
        "color-rating-bad", "color-rating-fair", "color-rating-good",
        "color-rating-excellent", "color-ttb-main", "color-ttb-extras",
        "color-ttb-completionist", "color-ttb-footage"
      )
    end

    it "freezes the hash" do
      expect(described_class::SEMANTIC).to be_frozen
    end

    it "routes color-danger to Dracula Pink (Q1 v4 lock)" do
      expect(described_class::SEMANTIC.fetch("color-danger")).to eq(described_class::DRACULA.fetch(:pink))
    end

    it "leaves color-link as a CSS variable reference so the cascade resolves at paint time" do
      expect(described_class::SEMANTIC.fetch("color-link")).to eq("var(--section-accent)")
    end

    it "pins TTB tokens to the canonical Dracula hues" do
      expect(described_class::SEMANTIC.fetch("color-ttb-main")).to          eq(described_class::DRACULA.fetch(:green))
      expect(described_class::SEMANTIC.fetch("color-ttb-extras")).to        eq(described_class::DRACULA.fetch(:cyan))
      expect(described_class::SEMANTIC.fetch("color-ttb-completionist")).to eq(described_class::DRACULA.fetch(:pink))
      expect(described_class::SEMANTIC.fetch("color-ttb-footage")).to       eq(described_class::DRACULA.fetch(:fg))
    end
  end

  describe ".atoms" do
    it "returns the DRACULA hash" do
      expect(described_class.atoms).to be(described_class::DRACULA)
    end
  end

  describe ".section_accent" do
    it "returns the mapped accent for a known section" do
      expect(described_class.section_accent("settings")).to eq(described_class::DRACULA.fetch(:orange))
    end

    it "looks up via to_s so symbol callers work too" do
      expect(described_class.section_accent(:games)).to eq(described_class::PALE_COBALT)
    end

    it "falls back to Dracula Purple for unknown sections" do
      expect(described_class.section_accent("nope")).to eq(described_class::DRACULA.fetch(:purple))
    end

    it "falls back to Dracula Purple for nil" do
      expect(described_class.section_accent(nil)).to eq(described_class::DRACULA.fetch(:purple))
    end
  end

  describe ".section_bg" do
    it "returns the mapped bg for a known section" do
      expect(described_class.section_bg("settings")).to eq("#34333b")
    end

    it "falls back to Dracula bg for unknown sections" do
      expect(described_class.section_bg("nope")).to eq(described_class::DRACULA.fetch(:bg))
    end
  end

  describe ".section_border" do
    it "delegates to Pito::Theme::Sections.section_border" do
      expect(described_class.section_border("settings")).to eq(Pito::Theme::Sections.section_border("settings"))
    end

    it "computes the user-locked settings border (35% orange on #34333b)" do
      expect(described_class.section_border("settings")).to eq("#7b624c")
    end
  end

  describe ".color_link_hover" do
    it "mixes the section accent 80% toward white" do
      # settings accent #ffb86c -> (255, 184, 108); white -> (255, 255, 255)
      # r = 255 + (255 - 255) * 0.80 = 255 -> 0xff
      # g = 255 + (184 - 255) * 0.80 = 198.2 -> 198 -> 0xc6
      # b = 255 + (108 - 255) * 0.80 = 137.4 -> 137 -> 0x89
      expect(described_class.color_link_hover("settings")).to eq("#ffc689")
    end
  end

  describe ".color_focus_ring" do
    it "mixes the section accent 40% toward the section bg (hex approximation)" do
      # accent #ffb86c on bg #34333b at 40%
      # r = 52 + (255-52)*0.40 = 133.2 -> 133 -> 0x85
      # g = 51 + (184-51)*0.40 = 104.2 -> 104 -> 0x68
      # b = 59 + (108-59)*0.40 = 78.6  -> 79  -> 0x4f
      expect(described_class.color_focus_ring("settings")).to eq("#85684f")
    end
  end

  describe ".export_css" do
    let(:css) { described_class.export_css }

    it "wraps the output in a `:root { ... }` block" do
      expect(css).to start_with(":root {\n")
      expect(css).to end_with("}\n")
    end

    it "declares every L1 Dracula atom" do
      expect(css).to include("--dracula-bg: #282a36;")
      expect(css).to include("--dracula-current-line: #44475a;")
      expect(css).to include("--dracula-purple: #bd93f9;")
      expect(css).to include("--pale-cobalt: #7eb6ff;")
    end

    it "declares every section accent and the default cascade source" do
      expect(css).to include("--section-accent-home: #bd93f9;")
      expect(css).to include("--section-accent-channels: #ff5555;")
      expect(css).to include("--section-accent-games: #7eb6ff;")
      expect(css).to include("--section-accent-settings: #ffb86c;")
      expect(css).to include("--section-accent: var(--section-accent-home);")
    end

    it "declares every per-section bg atom" do
      expect(css).to include("--bg-section-home: #2c2a36;")
      expect(css).to include("--bg-section-channels: #36292d;")
      expect(css).to include("--bg-section-games: #292c33;")
      expect(css).to include("--bg-section-settings: #34333b;")
    end

    it "declares the canonical semantic tokens" do
      expect(css).to include("--color-bg: #282a36;")
      expect(css).to include("--color-text: #f8f8f2;")
      expect(css).to include("--color-danger: #ff79c6;")
      expect(css).to include("--color-link: var(--section-accent);")
    end

    it "ends with a trailing newline" do
      expect(css[-1]).to eq("\n")
    end
  end

  describe ".export_rust" do
    let(:rust) { described_class.export_rust }

    it "starts with the auto-generated header (used by the rake task safety guard)" do
      expect(rust).to start_with("// Auto-generated by `rake pito:theme:export`.")
    end

    it "wraps the constants in a `pub mod theme` block" do
      expect(rust).to include("pub mod theme {")
      expect(rust).to end_with("}\n")
    end

    it "exposes every Dracula atom as a pub const &str hex literal" do
      expect(rust).to include('pub const DRACULA_BG: &str = "#282a36";')
      expect(rust).to include('pub const DRACULA_FG: &str = "#f8f8f2";')
      expect(rust).to include('pub const DRACULA_PURPLE: &str = "#bd93f9";')
      expect(rust).to include('pub const PALE_COBALT: &str = "#7eb6ff";')
    end

    it "exposes every section accent and section bg" do
      expect(rust).to include('pub const SECTION_ACCENT_HOME: &str = "#bd93f9";')
      expect(rust).to include('pub const SECTION_ACCENT_SETTINGS: &str = "#ffb86c";')
      expect(rust).to include('pub const SECTION_BG_SETTINGS: &str = "#34333b";')
    end

    it "exposes hex-valued semantic tokens as upper-snake-case constants" do
      expect(rust).to include('pub const COLOR_BG: &str = "#282a36";')
      expect(rust).to include('pub const COLOR_DANGER: &str = "#ff79c6";')
      expect(rust).to include('pub const COLOR_TTB_MAIN: &str = "#50fa7b";')
    end

    it "SKIPS semantic tokens whose value is a CSS var() reference (no Ratatui cascade)" do
      expect(rust).not_to include("COLOR_LINK")
    end
  end
end
