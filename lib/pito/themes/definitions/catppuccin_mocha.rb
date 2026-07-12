require_relative "../registry"

# Catppuccin Mocha — canonical Catppuccin Mocha (dark) palette.
Pito::Themes::Registry.register(
  slug:  "catppuccin-mocha",
  label: "Catppuccin Mocha",
  mode:  :dark,
  base: {
    bg:     "#1e1e2e",
    fg:     "#cdd6f4",
    purple: "#cba6f7",
    blue:   "#89b4fa",
    cyan:   "#94e2d5",
    green:  "#a6e3a1",
    yellow: "#f9e2af",
    orange: "#fab387",
    red:    "#f38ba8"
  },
  overrides: {
    surface:  "#313244",
    elevated: "#45475a"
  }
)
