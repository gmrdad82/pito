module Settings
  module Stack
    module Sidekiq
      # Renders the Redis-pane Sidekiq counters block — two separate
      # `.stack-table`s sharing a `table-layout: fixed` 5-column grid so
      # the 2-col lifetime row (successful / failed) aligns under the
      # 5-col queue row (busy / scheduled / enqueued / retry / dead).
      #
      # Extracted from `app/views/settings/_stack_pane.html.erb`
      # (lines ~101-193) per Beta-3 lane B candidate B9. The wrapping
      # `<div>` stays so the vertical spacing keeps reading as one
      # Redis-stats block.
      #
      # Alignment invariant: `successful` lands under `enqueued` (col 3),
      # `failed` lands under `dead` (col 5). Cols 1, 2, 4 of the
      # lifetime table are spacer cells. The 5 equal-width columns in
      # both tables' colgroups keep the alignment honest.
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
      end
    end
  end
end
