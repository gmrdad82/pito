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
  #
  # `csv:` opts the chip into comma-separated multi-value mode (Phase 15
  # calendar restructure). In csv mode `current_params[@param]` is treated
  # as a comma-separated list; `checked?` is membership in that list, and
  # `href` toggles `@value`'s membership (adding it if absent, removing it
  # if present). When the resulting list is empty the param is preserved
  # with an empty value (`?types=`) so the URL still encodes the
  # "everything unchecked" state distinctly from "no param = all". The
  # default (no `csv:`) keeps the original single-value semantics.
  def initialize(label:, param:, value: "yes", current_params: {}, frame: nil, csv: false)
    @label = label
    @param = param.to_s
    @value = value.to_s
    @current_params = (current_params || {}).to_h.transform_keys(&:to_s)
    @frame = frame
    @csv = csv
  end

  def checked?
    if @csv
      csv_values.include?(@value)
    else
      @current_params[@param].to_s == @value
    end
  end

  def href
    new_params = @current_params.dup

    if @csv
      values = csv_values
      if values.include?(@value)
        values -= [ @value ]
      else
        values = (values + [ @value ]).uniq
      end
      # Preserve the param even when empty so the URL still distinguishes
      # "all unchecked" (`?types=`) from "no param = all".
      new_params[@param] = values.join(",")
    else
      if checked?
        new_params.delete(@param)
      else
        new_params[@param] = @value
      end
    end

    new_params.empty? ? "?" : "?#{new_params.to_query}"
  end

  def turbo_frame_attr
    @frame
  end

  private

  def csv_values
    raw = @current_params[@param]
    return [] if raw.nil?
    raw.to_s.split(",").map(&:strip).reject(&:empty?)
  end
end
