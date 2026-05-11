class CheckboxComponent < ViewComponent::Base
  def initialize(label: nil, checked: false, value: nil, data: {}, name: nil, variant: nil, disabled: false)
    @label = label
    @checked = checked
    @value = value
    @data = data
    @name = name
    @variant = variant
    @disabled = disabled
  end

  def wrapper_class
    @variant == :link ? "md-check md-check-link" : "md-check"
  end
end
