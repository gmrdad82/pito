class CheckboxComponent < ViewComponent::Base
  def initialize(label: nil, checked: false, value: nil, data: {}, name: nil)
    @label = label
    @checked = checked
    @value = value
    @data = data
    @name = name
  end
end
