class FormFieldComponent < ViewComponent::Base
  def initialize(form:, field:, label: nil, type: :text_field, rows: nil, collection: nil, options: nil, prompt: nil)
    @form = form
    @field = field
    @label = label || field.to_s.humanize(capitalize: false)
    @type = type
    @rows = rows
    @collection = collection
    @options = options
    @prompt = prompt
  end

  def errors
    @form.object.errors[@field]
  end

  def has_errors?
    errors.any?
  end

  def error_style
    has_errors? ? " border-color: var(--color-danger);" : ""
  end
end
