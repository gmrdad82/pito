class BracketedLinkComponent < ViewComponent::Base
  # `confirm:` is intentionally unused here. The project rule forbids
  # `window.confirm` / `data-turbo-confirm`. Destructive flows go through
  # either the action confirmation page framework (/deletions, /syncs) or
  # an in-page modal via ConfirmModalComponent + modal-trigger controller.
  # The kwarg is preserved so existing call sites do not raise; track
  # for removal once all callers have migrated.
  def initialize(label:, href: nil, destructive: false, method: nil, data: {}, active: false, confirm: nil, target: nil, rel: nil)
    @label = label
    @href = href
    @destructive = destructive
    @method = method
    @data = data
    @active = active
    @confirm = confirm # deprecated, no longer rendered
    @target = target
    @rel = rel
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
    attrs
  end
end
