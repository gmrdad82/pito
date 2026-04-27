class ApplicationDecorator < Draper::Decorator
  delegate_all

  def formatted_number(value)
    h.number_with_delimiter(value || 0)
  end
end
