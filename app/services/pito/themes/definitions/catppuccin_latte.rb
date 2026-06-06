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
    elevated: "#bcc0cc",
    # The darker surface override pushes the derived fg-dim/fg-faded too close
    # to the surface (low-contrast chatbox text + timestamps). Pin them to
    # Catppuccin Latte's canonical subtext1 / overlay2 for readable muted text.
    fg_dim:   "#5c5f77",
    fg_faded: "#7c7f93"
  }
)
