class BracketedLinkComponent < ViewComponent::Base
  def initialize(label:, href: nil, destructive: false, method: nil, data: {}, active: false, confirm: nil)
    @label = label
    @href = href
    @destructive = destructive
    @method = method
    @data = data
    @active = active
    @confirm = confirm
  end

  def active?
    @active || @href.nil?
  end

  def css_classes
    classes = [ "bracketed" ]
    classes << "text-danger" if @destructive
    classes.join(" ")
  end

  def html_data
    attrs = @data.dup
    attrs[:turbo_method] = @method if @method
    attrs[:turbo_confirm] = @confirm if @confirm
    attrs
  end
end
