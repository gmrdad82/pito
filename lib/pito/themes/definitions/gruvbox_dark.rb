require_relative "../registry"

# Gruvbox Dark — canonical Gruvbox dark palette.
Pito::Themes::Registry.register(
  slug:  "gruvbox-dark",
  label: "Gruvbox Dark",
  mode:  :dark,
  base: {
    bg:     "#282828",
    fg:     "#ebdbb2",
    purple: "#d3869b",
    blue:   "#83a598",
    cyan:   "#8ec07c",
    green:  "#b8bb26",
    yellow: "#fabd2f",
    orange: "#fe8019",
    red:    "#fb4934"
  },
  overrides: {
    surface:  "#3c3836",
    elevated: "#504945"
  }
)
