require_relative "../registry"

# Tomorrow Night — canonical Tomorrow Night dark palette.
Pito::Themes::Registry.register(
  slug:  "tomorrow-night",
  label: "Tomorrow Night",
  mode:  :dark,
  base: {
    bg:     "#1d1f21",
    fg:     "#c5c8c6",
    purple: "#b294bb",
    blue:   "#81a2be",
    cyan:   "#8abeb7",
    green:  "#b5bd68",
    yellow: "#f0c674",
    orange: "#de935f",
    red:    "#cc6666"
  },
  overrides: {
    surface:  "#282a2e",
    elevated: "#373b41"
  }
)
