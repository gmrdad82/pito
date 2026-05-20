module Settings
  module Stack
    module Sidekiq
      # Renders the Redis-tile Sidekiq counters block — two separate
      # `.tui-table--stack`s sharing a `table-layout: fixed` 5-column grid so
      # the 2-col lifetime row (successful / failed) aligns under the
      # 5-col queue row (busy / scheduled / enqueued / retry / dead).
      #
      # Extracted from `app/views/settings/_stack_pane.html.erb`
      # (lines ~101-193) per Beta-3 lane B candidate B9. Beta 4 F3-D
      # added per-state color rules that mirror the status-bar Sidekiq
      # segment in the top status bar (`.sb-sk-cell.sk-b` etc.):
      #
      #   busy       → success (green) when count > 0
      #   enqueued   → warn   (orange) when count > 0
      #   retry      → danger (pink)   when count > 0
      #   dead       → danger (pink)   when count > 0
      #   failed     → danger (pink)   when count > 0
      #   scheduled  → muted           always
      #   successful → default text    always
      #
      # When a state's count is zero (or absent), the cell rolls back
      # to muted — the "no signal" tonal floor — regardless of the
      # state-specific color above. This mirrors the status-bar
      # `.sk-zero` rule.
      #
      # The wrapping `<div>` stays so the vertical spacing keeps reading
      # as one Redis-stats block. Alignment invariant: `successful`
      # lands under `enqueued` (col 3), `failed` lands under `dead`
      # (col 5). Cols 1, 2, 4 of the lifetime table are spacer cells.
      # The 5 equal-width columns in both tables' colgroups keep the
      # alignment honest.
      #
      # Per-cell `data-stack-stats-live-target` attributes are preserved
      # verbatim — the `stack-stats-live` Stimulus controller patches
      # these cells every ~3 s from the `/settings/stack_stats` JSON
      # endpoint without a full-page reload.
      class CountersComponent < ViewComponent::Base
        # @param breakdown [Array<Hash>] each element is
        #   `{ label: <state>, count: <integer> }` where `<state>` is
        #   one of `"processed"`, `"failed"`, `"busy"`, `"scheduled"`,
        #   `"enqueued"`, `"retry"`, `"dead"` (the canonical shape
        #   produced by `SettingsController#sidekiq_breakdown_for_settings_pane`).
        def initialize(breakdown:)
          @breakdown = breakdown
        end

        QUEUE_STATES = %w[busy scheduled enqueued retry dead].freeze

        # Per-state tonal class. Resolves to a `tui-chip` color modifier
        # so the cell takes the same color token surface as the chip
        # primitive — `--color-success` (green) / `--dracula-orange`
        # (orange) / `--color-danger` (pink) / `--color-muted` (muted).
        # Reusing the chip modifier avoids declaring a new
        # `.stack-sk-cell` class family in CSS — the file is closed for
        # this dispatch.
        STATE_COLOR = {
          "busy"       => "tui-chip--success",
          "enqueued"   => "tui-chip--warn",
          "retry"      => "tui-chip--danger",
          "dead"       => "tui-chip--danger",
          "failed"     => "tui-chip--danger",
          "scheduled"  => "tui-chip--neutral",
          "processed"  => nil
        }.freeze

        # Internal lookup hash keyed by state label.
        def counts
          @counts ||= @breakdown.each_with_object({}) do |row, acc|
            acc[row[:label]] = row[:count]
          end
        end

        # Render-time helper — emits the formatted count or a dash.
        def cell_for(state)
          value = counts[state]
          value ? helpers.number_with_delimiter(value) : "—"
        end

        # Emits a CSS class string for the cell holding `state`. When
        # the count is zero / nil the cell rolls back to muted so the
        # green / orange / pink colors only surface on a real signal.
        def color_class_for(state)
          value = counts[state].to_i
          return "tui-chip--neutral" if value.zero?

          STATE_COLOR[state]
        end
      end
    end
  end
end
