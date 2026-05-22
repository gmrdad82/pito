module Tui
  # Beta 4 — D5 (2026-05-22). One row inside Tui::LeaderMenuComponent.
  #
  # Renders a single which-key entry: `<key> · <label>`. The key glyph
  # is dimmed to the section accent (via `.tui-leader-menu__key`), the
  # middle dot is muted, and the label sits in default text color. The
  # row carries `data-leader-key="<key>"` plus the per-entry data attrs
  # the Stimulus controller reads to decide how to fire when the user
  # presses `<key>`.
  #
  # Kwargs:
  #   key:   String — the next-key character (single char or two chars
  #          like `Sp` — kept flexible for future-proofing, but D5 ships
  #          single-char keys only).
  #   label: String — i18n-resolved row label.
  #   data:  Hash — extra data attributes forwarded to the row `<li>`.
  #          Caller MUST namespace keys under `leader-*` (consumer
  #          contract: `data-leader-key`, `data-leader-path`,
  #          `data-leader-action-name`, `data-leader-dispatch-method`,
  #          `data-leader-path-method`). The component does not inspect
  #          the values — the Stimulus controller does.
  class LeaderMenuEntryComponent < ViewComponent::Base
    def initialize(key:, label:, data: {})
      @key = key
      @label = label
      @data = data
    end

    attr_reader :key, :label, :data
  end
end
