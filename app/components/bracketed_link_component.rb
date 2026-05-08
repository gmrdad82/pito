class BracketedLinkComponent < ViewComponent::Base
  # Phase 7.5 — Step 01 hygiene sweep dropped the deprecated `confirm:`
  # kwarg. The project rule forbids `window.confirm` / `data-turbo-confirm`;
  # destructive flows go through either the action confirmation page
  # framework (/deletions, /syncs) or an in-page modal via
  # ConfirmModalComponent + modal-trigger controller.
  def initialize(label:, href: nil, destructive: false, method: nil, data: {}, active: false, target: nil, rel: nil)
    @label = label
    @href = href
    @destructive = destructive
    @method = method
    @data = data
    @active = active
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
