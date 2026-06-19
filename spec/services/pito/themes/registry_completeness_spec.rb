require "rails_helper"

# Registry completeness spec:
#   - Registry.all has exactly 19 themes
#   - Every theme resolves a complete token set with valid hex values
#   - brand_pito == "#5170ff" for every theme
#   - Registry.grouped splits into 12 dark + 7 light
RSpec.describe "Pito::Themes::Registry completeness" do
  EXPECTED_TOKEN_KEYS = %i[
    bg_root bg_surface bg_elevated
    border_default border_faded
    fg_default fg_dim fg_faded
    accent_purple accent_blue accent_cyan accent_green
    accent_yellow accent_orange accent_red
    brand_pito
  ].freeze

  VALID_HEX = /\A#[0-9a-f]{6}\z/

  let(:all_themes) { Pito::Themes::Registry.all }

  it "has exactly 19 themes" do
    expect(all_themes.size).to eq(19)
  end

  it "every theme resolves all required token keys" do
    all_themes.each do |theme|
      expect(theme.tokens.keys).to match_array(EXPECTED_TOKEN_KEYS),
        "#{theme.slug} is missing tokens"
    end
  end

  it "every token value is a valid 6-digit hex colour" do
    all_themes.each do |theme|
      theme.tokens.each do |key, value|
        expect(value).to match(VALID_HEX),
          "#{theme.slug}##{key} = #{value.inspect} is not a valid hex colour"
      end
    end
  end

  it "brand_pito is #5170ff on every theme" do
    all_themes.each do |theme|
      expect(theme.tokens[:brand_pito]).to eq("#5170ff"),
        "#{theme.slug} has wrong brand_pito: #{theme.tokens[:brand_pito].inspect}"
    end
  end

  describe "grouped dark/light split" do
    let(:grouped) { Pito::Themes::Registry.grouped }

    it "has exactly 12 dark themes" do
      expect(grouped[:dark].size).to eq(12)
    end

    it "has exactly 7 light themes" do
      expect(grouped[:light].size).to eq(7)
    end

    it "dark slugs include the expected themes" do
      dark_slugs = grouped[:dark].map(&:slug)
      expect(dark_slugs).to include(
        "tokyo-night", "dracula", "one-dark", "gruvbox-dark",
        "nord", "github-dark", "catppuccin-mocha",
        "ayu-dark", "ayu-mirage", "solarized-dark", "tomorrow-night",
        "synthwave"
      )
    end

    it "light slugs include the expected themes" do
      light_slugs = grouped[:light].map(&:slug)
      expect(light_slugs).to include(
        "one-light", "gruvbox-light", "github-light", "catppuccin-latte",
        "ayu-light", "solarized-light", "tomorrow"
      )
    end
  end
end
