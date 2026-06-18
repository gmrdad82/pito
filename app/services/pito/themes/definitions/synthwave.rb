require_relative "../registry"

# Synthwave dark theme — neon-on-indigo "outrun" palette.
#
# Deep-indigo backgrounds (#1a0b2e → #2d1259) with electric magenta/cyan accents.
# Sourced from the in-house ASCII-art demo palette the user picked; surface,
# elevated, the two fg dims, and both border tones are overridden so the rendered
# theme matches that demo exactly rather than using the derived Mix values.
#
# Synthwave's hot pink (#ff5cc8) has no corresponding pito accent token, so it is
# intentionally dropped — accent_red carries the magenta-red (#ff2e63) instead.
Pito::Themes::Registry.register(
  slug:  "synthwave",
  label: "Synthwave",
  mode:  :dark,
  base: {
    bg:     "#1a0b2e",
    fg:     "#f5e0ff",
    purple: "#b967ff",
    blue:   "#5d8bff",
    cyan:   "#00f0ff",
    green:  "#39ff88",
    yellow: "#ffe066",
    orange: "#ff8c42",
    red:    "#ff2e63"
  },
  overrides: {
    surface:        "#241046",
    elevated:       "#2d1259",
    fg_dim:         "#c4a7e7",
    fg_faded:       "#7a5c9e",
    border_default: "#3a1d6e",
    border_faded:   "#5a2d9e"
  }
)
