require_relative "../registry"

# Ayu Mirage — canonical Ayu Mirage (dark) palette.
Pito::Themes::Registry.register(
  slug:  "ayu-mirage",
  label: "Ayu Mirage",
  mode:  :dark,
  base: {
    bg:     "#1f2430",
    fg:     "#e6e3d6",
    purple: "#d4bfff",
    blue:   "#73d0ff",
    cyan:   "#95e6cb",
    green:  "#bae67e",
    yellow: "#ffd580",
    orange: "#ffad66",
    red:    "#f28779"
  },
  overrides: {
    surface:  "#232834",
    elevated: "#2b3340"
  }
)
