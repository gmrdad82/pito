module Tui
  # Beta 4 — extracted from `Tui::TopStatusBarComponent` (2026-05-21)
  # per "ViewComponents are kings" — sub-elements of the top status
  # bar each get their own VC + spec.
  #
  # Sidekiq queue-depth stats cells: `b<n> e<n> r<n>`. Each cell is
  # width-locked to 5 chars total — 1-char prefix (`b` / `e` / `r`) +
  # 4-char short-formatted value (`32  ` `1k  ` `999k` `1M  `). The
  # 4-char pad prevents word-jumping when broadcasts cascade values.
  #
  # Constructor inputs:
  #   - busy:        integer (default 0)
  #   - enqueued:    integer (default 0)
  #   - retry_count: integer (default 0)
  #
  # The `scheduled` count is intentionally NOT rendered here — the
  # bar shows three of the four counts. `scheduled` is a future
  # surface (per-subsystem stack panel).
  #
  # 2026-05-22 — Phase 2B rewires the three cells through the canonical
  # `Tui::Transitionable` mixin (scramble-settle + color-crossfade) and
  # short-formats values via `Pito::Formatter::ShortNumber`. The parent
  # `tui-sidekiq-stats` Stimulus controller listens for the
  # `tui:sidekiq-changed` event and walks each cell's colocated
  # `tui-transition` controller via `setValue(...)`.
  #
  # Color rules (locked 2026-05-22):
  #
  #   busy     → base :muted, active :success (green)
  #   enqueued → base :muted, active :warn    (orange)
  #   retry    → base :muted, active :danger  (pink)
  #
  # @contract see app/services/pito/formatter/short_number.rb
  # @contract see app/components/tui/transitionable.rb
  # @contract see app/javascript/controllers/tui_sidekiq_stats_controller.js
  class SidekiqStatsComponent < ViewComponent::Base
    include Tui::Transitionable

    # Short-format value width (chars). The full cell is 1 (prefix) + 4 (value).
    CELL_WIDTH = 4

    def initialize(busy: 0, enqueued: 0, retry_count: 0, **legacy)
      # `retry:` is accepted as a legacy kwarg for callers that still pass
      # it under the Ruby keyword form. New callers should use `retry_count:`.
      @busy        = busy.to_i
      @enqueued    = enqueued.to_i
      @retry_count = (legacy[:retry] || retry_count).to_i
    end

    # Ordered cell descriptors driving the template.
    def cells
      [
        { name: :busy,     prefix: "b", value: @busy,        active_color: :success },
        { name: :enqueued, prefix: "e", value: @enqueued,    active_color: :warn },
        { name: :retry,    prefix: "r", value: @retry_count, active_color: :danger }
      ]
    end

    # Short-format the raw value then right-pad with spaces to CELL_WIDTH.
    # Returns the exact string the user sees inside a cell (post-prefix).
    def display_value(raw)
      Pito::Formatter::ShortNumber.call(raw).ljust(CELL_WIDTH)
    end

    # Build the data-attrs payload for one cell — combines the
    # `tui-transition` controller (via Transitionable mixin) with the
    # cell-name marker the parent `tui-sidekiq-stats` controller uses to
    # locate each cell on `tui:sidekiq-changed`.
    def cell_data(cell)
      base = transitionable_attrs(
        value: display_value(cell[:value]),
        color: :muted,
        active_color: cell[:active_color],
        prefix: cell[:prefix]
      )
      base[:data][:tui_sidekiq_stats_cell_name_value] = cell[:name].to_s
      base[:data]
    end
  end
end
