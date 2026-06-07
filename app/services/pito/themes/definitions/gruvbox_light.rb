require_relative "../registry"

# Gruvbox Light — canonical Gruvbox light palette.
Pito::Themes::Registry.register(
  slug:  "gruvbox-light",
  label: "Gruvbox Light",
  mode:  :light,
  base: {
    bg:     "#fbf1c7",
    fg:     "#3c3836",
    purple: "#b16286",
    blue:   "#458588",
    cyan:   "#689d6a",
    green:  "#98971a",
    yellow: "#d79921",
    orange: "#d65d0e",
    red:    "#cc241d"
  },
  overrides: {
    surface:  "#ebdbb2",
    elevated: "#d5c4a1"
  }
)
