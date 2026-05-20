module Tui
  # Beta 4 — Phase F2. TUI checkbox primitive. Renders `[ ]` / `[x]`
  # as the universal selection / toggle marker — per ADR 0016's
  # destructive action pattern: `[x]` selects rows + confirmation
  # dialog confirms + cable removes. ONE pattern for every
  # destructive flow.
  #
  # Three render modes, picked by the constructor args:
  #
  #   * `href:` given        -> renders as `<a>` (URL-param toggle, used
  #                             by `FilterChipComponent` and similar).
  #   * `name:` given (no href)
  #                           -> renders as `<label>` wrapping a hidden
  #                              `name=no` input + the visible checkbox,
  #                              guaranteeing the form post always
  #                              receives `yes` or `no` (per pito's hard
  #                              rule: "yes / no for external booleans").
  #   * neither given        -> renders as inert `<span>` (display-only
  #                             marker — e.g. row selection state
  #                             rendered server-side without a form).
  #
  # The label argument is optional — bare `[x]` is fine for tight cells.
  # When provided, it renders after the box with one leading space, so
  # the rendered glyph is `[x] label` (the character grid stays
  # predictable).
  class CheckboxComponent < ViewComponent::Base
    def initialize(label: nil, checked: false, name: nil, value: "yes", href: nil)
      @label = label
      @checked = !!checked
      @name = name
      @value = value
      @href = href
    end

    attr_reader :label, :checked, :name, :value, :href

    def glyph
      checked ? "x" : " "
    end

    def renders_as_link?
      !href.nil?
    end

    def renders_as_form_input?
      !name.nil? && href.nil?
    end
  end
end
