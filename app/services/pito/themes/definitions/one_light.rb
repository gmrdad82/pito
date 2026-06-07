require_relative "../registry"

# One Light — Atom One Light palette.
Pito::Themes::Registry.register(
  slug:  "one-light",
  label: "One Light",
  mode:  :light,
  base: {
    bg:     "#fafafa",
    fg:     "#383a42",
    purple: "#a626a4",
    blue:   "#4078f2",
    cyan:   "#0184bc",
    green:  "#50a14f",
    yellow: "#c18401",
    orange: "#986801",
    red:    "#e45649"
  },
  overrides: {}
)
