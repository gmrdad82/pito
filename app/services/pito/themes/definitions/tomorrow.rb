require_relative "../registry"

# Tomorrow — canonical Tomorrow light palette.
Pito::Themes::Registry.register(
  slug:  "tomorrow",
  label: "Tomorrow",
  mode:  :light,
  base: {
    bg:     "#ffffff",
    fg:     "#4d4d4c",
    purple: "#8959a8",
    blue:   "#4271ae",
    cyan:   "#3e999f",
    green:  "#718c00",
    yellow: "#eab700",
    orange: "#f5871f",
    red:    "#c82829"
  },
  overrides: {
    surface:  "#efefef",
    elevated: "#d6d6d6"
  }
)
