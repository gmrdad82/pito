require_relative "../registry"

# GitHub Light — canonical GitHub light palette.
Pito::Themes::Registry.register(
  slug:  "github-light",
  label: "GitHub Light",
  mode:  :light,
  base: {
    bg:     "#ffffff",
    fg:     "#24292f",
    purple: "#8250df",
    blue:   "#0969da",
    cyan:   "#1b7c83",
    green:  "#1a7f37",
    yellow: "#9a6700",
    orange: "#bc4c00",
    red:    "#cf222e"
  },
  overrides: {
    surface:  "#f6f8fa",
    elevated: "#eaeef2"
  }
)
