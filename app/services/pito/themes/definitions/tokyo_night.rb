require_relative "../registry"

# Tokyo Night dark theme — migrated exactly from Pito::Theme::TOKYO_NIGHT.
#
# All surface/border/dim tokens are provided as overrides so the resolved CSS
# matches the hand-written block that existed before the data-driven engine.
# The override values were taken directly from the original theme constants.
Pito::Themes::Registry.register(
  slug:  "tokyo-night",
  label: "Tokyo Night",
  mode:  :dark,
  base: {
    bg:     "#1a1b26",
    fg:     "#c0caf5",
    purple: "#bb9af7",
    blue:   "#7aa2f7",
    cyan:   "#7dcfff",
    green:  "#9ece6a",
    yellow: "#e0af68",
    orange: "#ff9e64",
    red:    "#f7768e"
  },
  overrides: {
    surface:        "#1f2335",
    elevated:       "#24283b",
    border_default: "#292e42",
    border_faded:   "#414868",
    fg_dim:         "#565f89",
    fg_faded:       "#414868"
  }
)
