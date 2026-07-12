require_relative "../registry"

# One Dark — Atom One Dark palette.
Pito::Themes::Registry.register(
  slug:  "one-dark",
  label: "One Dark",
  mode:  :dark,
  base: {
    bg:     "#282c34",
    fg:     "#abb2bf",
    purple: "#c678dd",
    blue:   "#61afef",
    cyan:   "#56b6c2",
    green:  "#98c379",
    yellow: "#e5c07b",
    orange: "#d19a66",
    red:    "#e06c75"
  },
  overrides: {
    surface:  "#21252b",
    elevated: "#2c313a"
  }
)
