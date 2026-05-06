class FilterChipComponent < ViewComponent::Base
  # Bracketed-checkbox style filter chip. The whole chip is an anchor that
  # toggles a single URL parameter on/off. All other URL params are preserved
  # so chips compose with each other and with pagination/search state.
  #
  # Visual-only [x] / [ ] indicator (no real form input) — clicking the
  # anchor performs the toggle via standard navigation. URL is the single
  # source of truth for filter state (no JS, no localStorage, no cookies).
  #
  # `frame:` opts the chip into Turbo Frame navigation. When set, the
  # anchor carries `data-turbo-frame="<frame-id>"` and
  # `data-turbo-action="advance"` so a click only swaps the matching
  # frame on the page (rather than navigating the whole page) AND
  # updates the URL bar. Mirrors `ApplicationHelper#sort_link_to(frame:)`.
  def initialize(label:, param:, value: "yes", current_params: {}, frame: nil)
    @label = label
    @param = param.to_s
    @value = value.to_s
    @current_params = (current_params || {}).to_h.transform_keys(&:to_s)
    @frame = frame
  end

  def checked?
    @current_params[@param].to_s == @value
  end

  def href
    new_params = @current_params.dup
    if checked?
      new_params.delete(@param)
    else
      new_params[@param] = @value
    end
    new_params.empty? ? "?" : "?#{new_params.to_query}"
  end

  def turbo_frame_attr
    @frame
  end
end
