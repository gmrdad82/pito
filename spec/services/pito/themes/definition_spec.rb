require "rails_helper"

RSpec.describe Pito::Themes::Definition do
  # Full set of token keys that every theme must resolve
  ALL_TOKEN_KEYS = %i[
    bg_root bg_surface bg_elevated
    border_default border_faded
    fg_default fg_dim fg_faded
    accent_purple accent_blue accent_cyan accent_green
    accent_yellow accent_orange accent_red
    brand_pito
  ].freeze

  HEX_PATTERN = /\A#[0-9a-f]{6}\z/

  let(:minimal_raw) do
    {
      slug:  "test-dark",
      label: "Test Dark",
      mode:  :dark,
      base: {
        bg:     "#000000",
        fg:     "#ffffff",
        purple: "#aa00aa",
        blue:   "#0000aa",
        cyan:   "#00aaaa",
        green:  "#00aa00",
        yellow: "#aaaa00",
        orange: "#aa5500",
        red:    "#aa0000"
      },
      overrides: {}
    }
  end

  let(:definition) { described_class.from_raw(minimal_raw) }

  describe ".from_raw" do
    it "produces all required token keys" do
      expect(definition.tokens.keys).to match_array(ALL_TOKEN_KEYS)
    end

    it "all token values are valid hex strings" do
      definition.tokens.each do |key, value|
        expect(value).to match(HEX_PATTERN), "token #{key} = #{value.inspect} is not a valid hex colour"
      end
    end

    it "sets bg_root from base[:bg]" do
      expect(definition.tokens[:bg_root]).to eq("#000000")
    end

    it "sets fg_default from base[:fg]" do
      expect(definition.tokens[:fg_default]).to eq("#ffffff")
    end

    it "auto-derives bg_surface as mix(bg, fg, 0.06)" do
      expected = Pito::Themes::Mix.call("#000000", "#ffffff", 0.06)
      expect(definition.tokens[:bg_surface]).to eq(expected)
    end

    it "auto-derives bg_elevated as mix(bg, fg, 0.12)" do
      expected = Pito::Themes::Mix.call("#000000", "#ffffff", 0.12)
      expect(definition.tokens[:bg_elevated]).to eq(expected)
    end

    it "auto-derives border_default as mix(bg, fg, 0.16)" do
      expected = Pito::Themes::Mix.call("#000000", "#ffffff", 0.16)
      expect(definition.tokens[:border_default]).to eq(expected)
    end

    it "auto-derives border_faded as mix(bg, fg, 0.28)" do
      expected = Pito::Themes::Mix.call("#000000", "#ffffff", 0.28)
      expect(definition.tokens[:border_faded]).to eq(expected)
    end

    it "auto-derives fg_dim as mix(fg, bg, 0.40)" do
      expected = Pito::Themes::Mix.call("#ffffff", "#000000", 0.40)
      expect(definition.tokens[:fg_dim]).to eq(expected)
    end

    it "auto-derives fg_faded as mix(fg, bg, 0.60)" do
      expected = Pito::Themes::Mix.call("#ffffff", "#000000", 0.60)
      expect(definition.tokens[:fg_faded]).to eq(expected)
    end

    it "brand_pito is always #5170ff regardless of base colours" do
      expect(definition.tokens[:brand_pito]).to eq("#5170ff")
    end

    context "with overrides" do
      let(:raw_with_overrides) do
        minimal_raw.merge(
          overrides: {
            surface:        "#111111",
            elevated:       "#222222",
            border_default: "#333333",
            border_faded:   "#444444",
            fg_dim:         "#555555",
            fg_faded:       "#666666"
          }
        )
      end

      let(:overridden) { described_class.from_raw(raw_with_overrides) }

      it "surface override wins over derived bg_surface" do
        expect(overridden.tokens[:bg_surface]).to eq("#111111")
      end

      it "elevated override wins over derived bg_elevated" do
        expect(overridden.tokens[:bg_elevated]).to eq("#222222")
      end

      it "border_default override wins over derived" do
        expect(overridden.tokens[:border_default]).to eq("#333333")
      end

      it "border_faded override wins over derived" do
        expect(overridden.tokens[:border_faded]).to eq("#444444")
      end

      it "fg_dim override wins over derived" do
        expect(overridden.tokens[:fg_dim]).to eq("#555555")
      end

      it "fg_faded override wins over derived" do
        expect(overridden.tokens[:fg_faded]).to eq("#666666")
      end

      it "brand_pito is still #5170ff after overrides" do
        expect(overridden.tokens[:brand_pito]).to eq("#5170ff")
      end
    end

    context "with a light mode theme" do
      let(:light_raw) do
        {
          slug:  "test-light",
          label: "Test Light",
          mode:  :light,
          base: {
            bg:     "#ffffff",
            fg:     "#1a1b26",
            purple: "#7000aa",
            blue:   "#0055ff",
            cyan:   "#0099aa",
            green:  "#007700",
            yellow: "#886600",
            orange: "#cc4400",
            red:    "#cc0000"
          },
          overrides: {}
        }
      end

      let(:light_def) { described_class.from_raw(light_raw) }

      it "resolves all token keys" do
        expect(light_def.tokens.keys).to match_array(ALL_TOKEN_KEYS)
      end

      it "mode is :light" do
        expect(light_def.mode).to eq(:light)
      end

      it "all token values are valid hex strings" do
        light_def.tokens.each do |key, value|
          expect(value).to match(HEX_PATTERN), "token #{key} = #{value.inspect}"
        end
      end

      it "brand_pito is always #5170ff" do
        expect(light_def.tokens[:brand_pito]).to eq("#5170ff")
      end
    end
  end
end
