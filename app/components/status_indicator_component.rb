class StatusIndicatorComponent < ViewComponent::Base
  CSS_CLASSES = {
    up: "indicator-up",
    down: "indicator-down",
    flat: "indicator-flat",
    loading: "dot-loader",
    done: "dot-done",
    fail: "dot-fail"
  }.freeze

  def initialize(kind:, text:, sort_value: nil, loader_delay: nil)
    @kind = kind.to_sym
    @text = text
    @sort_value = sort_value
    @loader_delay = loader_delay
  end

  def css_class
    CSS_CLASSES[@kind]
  end

  def data_attrs
    @sort_value ? { sort_value: @sort_value } : {}
  end

  def style_attr
    @loader_delay ? "--loader-delay: #{@loader_delay}" : nil
  end
end
