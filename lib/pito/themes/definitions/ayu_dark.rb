require_relative "../registry"

# Ayu Dark — canonical Ayu dark palette.
Pito::Themes::Registry.register(
  slug:  "ayu-dark",
  label: "Ayu Dark",
  mode:  :dark,
  base: {
    bg:     "#0b0e14",
    fg:     "#bfbdb6",
    purple: "#d2a6ff",
    blue:   "#59c2ff",
    cyan:   "#95e6cb",
    green:  "#aad94c",
    yellow: "#e6b450",
    orange: "#ff8f40",
    red:    "#f07178"
  },
  overrides: {
    surface:  "#11151c",
    elevated: "#1c212b"
  }
)
