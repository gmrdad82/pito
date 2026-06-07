require_relative "../registry"

# Dracula dark theme — canonical Dracula palette.
#
# accent_blue is mapped to Dracula's "comment" blue (#6272a4), which is a
# distinct blue-grey in the Dracula family, clearly different from purple
# (#bd93f9). Surface, elevated, border, and dim tokens use overrides to
# match canonical Dracula bg-lighter values (#44475a for elevated/borders).
#
# Dracula pink (#ff79c6) is the canonical "pink" accent — it is not part of
# the standard token set but is available as a named override if future tokens
# are added. For now the accent set maps pink to accent_red for distinction
# (Dracula red = #ff5555 is used as the canonical red accent).
Pito::Themes::Registry.register(
  slug:  "dracula",
  label: "Dracula",
  mode:  :dark,
  base: {
    bg:     "#282a36",
    fg:     "#f8f8f2",
    purple: "#bd93f9",
    blue:   "#6272a4",
    cyan:   "#8be9fd",
    green:  "#50fa7b",
    yellow: "#f1fa8c",
    orange: "#ffb86c",
    red:    "#ff5555"
  },
  overrides: {
    elevated:       "#44475a",
    border_default: "#44475a",
    border_faded:   "#6272a4",
    fg_dim:         "#6272a4"
  }
)
