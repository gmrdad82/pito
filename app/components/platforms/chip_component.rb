class Platforms::ChipComponent < ViewComponent::Base
  SLUG_BRAND = {
    "ps"     => { label: "PS",     color: "#003791" },
    "switch" => { label: "Switch", color: "#E60012" },
    "steam"  => { label: "Steam",  color: "#00ADEE" }
  }.freeze

  def initialize(slug:, size: :sm)
    @slug = slug.to_s
    @size = size  # :sm (tile footer, 12px), :md (detail page, 14px). Future: :lg.
  end

  def render?
    SLUG_BRAND.key?(@slug)
  end

  def label
    SLUG_BRAND.dig(@slug, :label)
  end

  def color
    SLUG_BRAND.dig(@slug, :color)
  end

  def size_class
    { sm: "platform-chip--sm", md: "platform-chip--md" }.fetch(@size)
  end
end
