require_relative "../registry"

# Ayu Light — canonical Ayu light palette.
Pito::Themes::Registry.register(
  slug:  "ayu-light",
  label: "Ayu Light",
  mode:  :light,
  base: {
    bg:     "#fcfcfc",
    fg:     "#5c6166",
    purple: "#a37acc",
    blue:   "#399ee6",
    cyan:   "#4cbf99",
    green:  "#86b300",
    yellow: "#f2ae49",
    orange: "#fa8d3e",
    red:    "#f07171"
  },
  overrides: {
    surface:  "#f3f4f5",
    elevated: "#e7eaed"
  }
)
