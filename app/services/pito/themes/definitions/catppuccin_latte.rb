require_relative "../registry"

# Catppuccin Latte — canonical Catppuccin Latte (light) palette.
Pito::Themes::Registry.register(
  slug:  "catppuccin-latte",
  label: "Catppuccin Latte",
  mode:  :light,
  base: {
    bg:     "#eff1f5",
    fg:     "#4c4f69",
    purple: "#8839ef",
    blue:   "#1e66f5",
    cyan:   "#179299",
    green:  "#40a02b",
    yellow: "#df8e1d",
    orange: "#fe640b",
    red:    "#d20f39"
  },
  overrides: {
    surface:  "#ccd0da",
    elevated: "#bcc0cc"
  }
)
