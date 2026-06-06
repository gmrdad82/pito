require_relative "../registry"

# Nord — canonical Nord dark palette.
Pito::Themes::Registry.register(
  slug:  "nord",
  label: "Nord",
  mode:  :dark,
  base: {
    bg:     "#2e3440",
    fg:     "#d8dee9",
    purple: "#b48ead",
    blue:   "#81a1c1",
    cyan:   "#88c0d0",
    green:  "#a3be8c",
    yellow: "#ebcb8b",
    orange: "#d08770",
    red:    "#bf616a"
  },
  overrides: {
    surface:  "#3b4252",
    elevated: "#434c5e"
  }
)
