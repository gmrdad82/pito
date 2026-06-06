require_relative "../registry"

# GitHub Dark — canonical GitHub dark palette.
Pito::Themes::Registry.register(
  slug:  "github-dark",
  label: "GitHub Dark",
  mode:  :dark,
  base: {
    bg:     "#0d1117",
    fg:     "#c9d1d9",
    purple: "#bc8cff",
    blue:   "#58a6ff",
    cyan:   "#39c5cf",
    green:  "#3fb950",
    yellow: "#d29922",
    orange: "#f0883e",
    red:    "#ff7b72"
  },
  overrides: {
    surface:  "#161b22",
    elevated: "#21262d"
  }
)
