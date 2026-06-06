require_relative "../registry"

# Solarized Dark — canonical Solarized dark palette.
Pito::Themes::Registry.register(
  slug:  "solarized-dark",
  label: "Solarized Dark",
  mode:  :dark,
  base: {
    bg:     "#002b36",
    fg:     "#839496",
    purple: "#6c71c4",
    blue:   "#268bd2",
    cyan:   "#2aa198",
    green:  "#859900",
    yellow: "#b58900",
    orange: "#cb4b16",
    red:    "#dc322f"
  },
  overrides: {
    surface:  "#073642",
    elevated: "#0a4a59"
  }
)
