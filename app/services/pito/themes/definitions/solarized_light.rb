require_relative "../registry"

# Solarized Light — canonical Solarized light palette.
Pito::Themes::Registry.register(
  slug:  "solarized-light",
  label: "Solarized Light",
  mode:  :light,
  base: {
    bg:     "#fdf6e3",
    fg:     "#657b83",
    purple: "#6c71c4",
    blue:   "#268bd2",
    cyan:   "#2aa198",
    green:  "#859900",
    yellow: "#b58900",
    orange: "#cb4b16",
    red:    "#dc322f"
  },
  overrides: {
    surface:  "#eee8d5",
    elevated: "#ddd6c1"
  }
)
