module Tui
  # Beta 4 — Phase F1 Lane B, refactored Phase 2 (2026-05-22).
  #
  # SidekiqStatsComponent renders Sidekiq queue-depth stats as a SINGLE
  # span: `b<n> e<n> r<n>`. No internal cells, no width-lock, no padding.
  # The whole value lives in one `tui-transition` host so length changes
  # cascade-scramble through downstream segments naturally.
  #
  # The colocated `tui-sidekiq-stats` Stimulus controller listens for
  # `tui:sidekiq-changed` document events, formats the new value as
  # `b<short(busy)> e<short(enqueued)> r<short(retry)>`, and pushes both
  # the new value and a segments JSON descriptor into the tui-transition
  # outlet for per-segment color routing.
  #
  # Constructor inputs:
  #   - busy:        integer (default 0)
  #   - enqueued:    integer (default 0)
  #   - retry_count: integer (default 0). Legacy `retry:` kwarg accepted.
  #
  # The `scheduled` count is intentionally NOT rendered here — a future
  # stack sub-panel surfaces it.
  #
  # Segment colors (locked 2026-05-22):
  #
  #   busy     → base :muted, active :success (green)
  #   enqueued → base :muted, active :warn    (orange)
  #   retry    → base :muted, active :danger  (pink)
  #
  # Active = the segment value is > 0. Color is driven by the
  # `.tt-char.tt-seg-<name>.is-active` CSS rules on the host.
  #
  # @contract see app/services/pito/formatter/short_number.rb
  # @contract see app/components/tui/transitionable.rb
  # @contract see app/javascript/controllers/tui_transition_controller.js
  # @contract see app/javascript/controllers/tui_sidekiq_stats_controller.js
  class SidekiqStatsComponent < ViewComponent::Base
    include Tui::Transitionable

    def initialize(busy: 0, enqueued: 0, retry_count: 0, **legacy)
      # `retry:` is accepted as a legacy kwarg for callers that still pass
      # it under the Ruby keyword form. New callers should use `retry_count:`.
      @busy        = busy.to_i
      @enqueued    = enqueued.to_i
      @retry_count = (legacy[:retry] || retry_count).to_i
    end

    # The full single-string value rendered into the span.
    def formatted_value
      "b#{short(@busy)} e#{short(@enqueued)} r#{short(@retry_count)}"
    end

    # Segments descriptor consumed by `tui-transition`'s segmentsValue.
    # Each entry: { name, range: [start, endExclusive], active }.
    def segments_json
      busy_str = "b#{short(@busy)}"
      enq_str  = "e#{short(@enqueued)}"
      ret_str  = "r#{short(@retry_count)}"
      bs = 0
      be = bs + busy_str.length
      es = be + 1 # +1 space separator
      ee = es + enq_str.length
      rs = ee + 1
      re = rs + ret_str.length
      [
        { name: "busy",     range: [ bs, be ], active: @busy > 0 },
        { name: "enqueued", range: [ es, ee ], active: @enqueued > 0 },
        { name: "retry",    range: [ rs, re ], active: @retry_count > 0 }
      ].to_json
    end

    # Build data-attrs Hash for the single host span. Merges the
    # transitionable base attrs with the segments descriptor.
    def transitionable_data
      attrs = transitionable_attrs(value: formatted_value, color: :muted)
      attrs[:data][:tui_transition_segments_value] = segments_json
      attrs
    end

    private

    def short(value)
      Pito::Formatter::ShortNumber.call(value)
    end
  end
end
