class CheckboxComponent < ViewComponent::Base
  def initialize(label: nil, checked: false, value: nil, data: {}, name: nil, variant: nil)
    @label = label
    @checked = checked
    @value = value
    @data = data
    @name = name
    @variant = variant
  end

  def wrapper_class
    @variant == :link ? "md-check md-check-link" : "md-check"
  end
end
