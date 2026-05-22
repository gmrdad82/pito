module Tui
  # Beta 4 — Phase F1 Lane B, refactored Phase 2 (2026-05-22).
  #
  # SidekiqStatsComponent renders Sidekiq queue-depth stats as a SINGLE
  # span: `b<n> e<n> r<n> d<n>`. No internal cells, no width-lock, no
  # padding. The whole value lives in one `tui-transition` host so
  # length changes cascade-scramble through downstream segments naturally.
  #
  # The colocated `tui-sidekiq-stats` Stimulus controller listens for
  # `tui:sidekiq-changed` document events, formats the new value as
  # `b<short(busy)> e<short(enqueued)> r<short(retry)> d<short(dead)>`,
  # and pushes both the new value and a segments JSON descriptor into
  # the tui-transition outlet for per-segment color routing.
  #
  # Constructor inputs:
  #   - busy:        integer (default 0)
  #   - enqueued:    integer (default 0)
  #   - retry_count: integer (default 0). Legacy `retry:` kwarg accepted.
  #   - dead:        integer (default 0). Dead set — jobs that exhausted
  #                  all retry attempts. Terminal failures, surfaced as
  #                  the `d<N>` segment with Dracula red when > 0.
  #   - concurrency: integer (default 10). Sidekiq's configured concurrency;
  #                  controls the busy/enqueued tier thresholds. Coerced
  #                  to >= 1 to avoid div-by-zero.
  #
  # The `scheduled` count is intentionally NOT rendered here — a future
  # stack sub-panel surfaces it.
  #
  # Concurrency-aware segment colors (locked 2026-05-22):
  #
  #   busy
  #     b == 0                          → muted
  #     ratio = busy/concurrency
  #     ratio <= 0.8                    → success
  #     0.8 < ratio < 1.0               → warn
  #     ratio == 1.0 AND enqueued > 0   → danger   (backpressure)
  #     ratio == 1.0 AND enqueued == 0  → warn     (saturated, no queue)
  #
  #   enqueued
  #     e == 0                          → muted
  #     mult = enqueued/concurrency
  #     mult <= 1.0                     → success
  #     1.0 < mult <= 2.0               → warn
  #     mult > 2.0                      → danger
  #
  #   retry    → r == 0 muted; r > 0 danger (flat)
  #   dead     → d == 0 muted; d > 0 fatal  (flat)
  #
  # Segments JSON entries carry `color: <name>` (replaces the old
  # `active: bool` shape). The tui_transition controller's
  # applySegments() reads the color field and applies `is-<color>`
  # classes per cell. The CSS exposes per-color rules:
  #   .tui-sidekiq-stats .tt-char.is-muted/.is-success/.is-warn/.is-danger/.is-fatal
  #
  # @contract see app/services/pito/formatter/short_number.rb
  # @contract see app/components/tui/transitionable.rb
  # @contract see app/javascript/controllers/tui_transition_controller.js
  # @contract see app/javascript/controllers/tui_sidekiq_stats_controller.js
  class SidekiqStatsComponent < ViewComponent::Base
    include Tui::Transitionable

    # Default Sidekiq concurrency used when no `concurrency:` kwarg is
    # given (SSR safety). The middleware broadcast carries the real
    # value; the JS controller mirrors this default.
    DEFAULT_CONCURRENCY = 10

    # The brand prefix (canonically capitalized "Sidekiq") is sourced from
    # `config/locales/tui/en.yml` at `tui.sidekiq.label` so the future Rust
    # TUI client consumes the same YAML. The prefix never changes between
    # broadcasts, so diff-only animateDiff leaves it untouched — only
    # segment cells scramble. The VC also emits the resolved value as a
    # Stimulus value (`data-tui-sidekiq-stats-prefix-value`) so the JS
    # controller mirrors it without hardcoding.
    def prefix
      I18n.t("tui.sidekiq.label")
    end

    def initialize(busy: 0, enqueued: 0, retry_count: 0, dead: 0, concurrency: DEFAULT_CONCURRENCY, **legacy)
      # `retry:` is accepted as a legacy kwarg for callers that still pass
      # it under the Ruby keyword form. New callers should use `retry_count:`.
      @busy        = busy.to_i
      @enqueued    = enqueued.to_i
      @retry_count = (legacy[:retry] || retry_count).to_i
      @dead        = dead.to_i
      # Coerce concurrency to a positive integer; avoid div-by-zero in
      # the tier methods. A misconfigured zero collapses to 1.
      @concurrency = [ concurrency.to_i, 1 ].max
    end

    # The full single-string value rendered into the span.
    def formatted_value
      "#{prefix} b#{short(@busy)} e#{short(@enqueued)} r#{short(@retry_count)} d#{short(@dead)}"
    end

    # Segments descriptor consumed by `tui-transition`'s segmentsValue.
    # Each entry: { name, range: [start, endExclusive], color: <name> }.
    def segments_json
      busy_str = "b#{short(@busy)}"
      enq_str  = "e#{short(@enqueued)}"
      ret_str  = "r#{short(@retry_count)}"
      dead_str = "d#{short(@dead)}"
      offset   = prefix.length + 1 # chars before the first segment starts (typ. 8)
      bs = offset
      be = bs + busy_str.length
      es = be + 1 # +1 space separator
      ee = es + enq_str.length
      rs = ee + 1
      re = rs + ret_str.length
      ds = re + 1
      de = ds + dead_str.length
      [
        { name: "busy",     range: [ bs, be ], color: busy_color },
        { name: "enqueued", range: [ es, ee ], color: enqueued_color },
        { name: "retry",    range: [ rs, re ], color: retry_color },
        { name: "dead",     range: [ ds, de ], color: dead_color }
      ].to_json
    end

    # Build data-attrs Hash for the single host span. Merges the
    # transitionable base attrs with the segments descriptor.
    def transitionable_data
      attrs = transitionable_attrs(value: formatted_value, color: :muted)
      attrs[:data][:tui_transition_segments_value] = segments_json
      attrs[:data][:tui_sidekiq_stats_prefix_value] = prefix
      attrs
    end

    private

    def short(value)
      Pito::Formatter::ShortNumber.call(value)
    end

    # Tier the busy segment by utilization against configured concurrency.
    # See class-level docblock for the truth table.
    def busy_color
      return "muted" if @busy.zero?
      ratio = @busy.to_f / @concurrency
      return "success" if ratio <= 0.8
      return "warn"    if ratio < 1.0
      @enqueued.positive? ? "danger" : "warn"
    end

    # Tier the enqueued segment by how many concurrency-windows of work
    # are parked behind the active set.
    def enqueued_color
      return "muted" if @enqueued.zero?
      mult = @enqueued.to_f / @concurrency
      return "success" if mult <= 1.0
      return "warn"    if mult <= 2.0
      "danger"
    end

    # Retry is flat: any retry is a problem signal.
    def retry_color
      @retry_count.positive? ? "danger" : "muted"
    end

    # Dead is flat + the most severe: any terminal failure is fatal.
    def dead_color
      @dead.positive? ? "fatal" : "muted"
    end
  end
end
