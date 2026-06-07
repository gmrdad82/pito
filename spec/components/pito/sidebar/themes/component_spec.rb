# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::Themes::Component do
  # Minimal theme stub that mimics Pito::Themes::Definition's public API.
  ThemeStub = Struct.new(:slug, :label, keyword_init: true)

  let(:tokyo_night)     { ThemeStub.new(slug: "tokyo-night",     label: "Tokyo Night")     }
  let(:dracula)         { ThemeStub.new(slug: "dracula",          label: "Dracula")          }
  let(:github_light)    { ThemeStub.new(slug: "github-light",     label: "GitHub Light")     }
  let(:catppuccin_latte) { ThemeStub.new(slug: "catppuccin-latte", label: "Catppuccin Latte") }

  def groups(dark: [], light: [])
    { dark: dark, light: light }
  end

  describe "Dark / Light grouping" do
    it "renders a row for each dark theme" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night, dracula ]),
          current_theme: "tokyo-night"
        )
      )
      expect(node.css(".pito-theme-row").size).to eq(2)
    end

    it "renders a row for each light theme" do
      node = render_inline(
        described_class.new(
          groups:        groups(light: [ github_light, catppuccin_latte ]),
          current_theme: "github-light"
        )
      )
      expect(node.css(".pito-theme-row").size).to eq(2)
    end

    it "renders both dark and light rows together" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night ], light: [ github_light ]),
          current_theme: "tokyo-night"
        )
      )
      expect(node.css(".pito-theme-row").size).to eq(2)
    end

    it "renders the theme label in each row" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night ], light: [ github_light ]),
          current_theme: "dracula"
        )
      )
      expect(node.to_html).to include("Tokyo Night")
      expect(node.to_html).to include("GitHub Light")
    end
  end

  describe "data-theme-name attribute" do
    it "sets data-theme-name on each row" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night, dracula ]),
          current_theme: "dracula"
        )
      )
      slugs = node.css(".pito-theme-row").map { |el| el["data-theme-name"] }
      expect(slugs).to contain_exactly("tokyo-night", "dracula")
    end
  end

  describe "current theme marking" do
    it "adds is-current class to the active theme row" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night, dracula ]),
          current_theme: "dracula"
        )
      )
      current_rows = node.css(".pito-theme-row.is-current")
      expect(current_rows.size).to eq(1)
      expect(current_rows.first["data-theme-name"]).to eq("dracula")
    end

    it "renders a cyan '← this one' marker on the current theme row (no bullet)" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night, dracula ]),
          current_theme: "tokyo-night"
        )
      )
      expect(node.to_html).to include("this one")
      expect(node.to_html).not_to include("●")
    end

    it "does not add is-current when current_theme matches no row" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night ]),
          current_theme: "dracula"
        )
      )
      expect(node.css(".pito-theme-row.is-current")).to be_empty
    end

    it "does not mark non-current rows" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night, dracula ]),
          current_theme: "tokyo-night"
        )
      )
      non_current = node.css(".pito-theme-row:not(.is-current)")
      expect(non_current.map { |el| el["data-theme-name"] }).to include("dracula")
    end
  end

  describe "pito--theme-nav mount point" do
    it "sets data-controller=pito--theme-nav on the list container" do
      node = render_inline(
        described_class.new(
          groups:        groups(dark: [ tokyo_night ]),
          current_theme: "tokyo-night"
        )
      )
      expect(node.css("[data-controller='pito--theme-nav']")).not_to be_empty
    end
  end
end
