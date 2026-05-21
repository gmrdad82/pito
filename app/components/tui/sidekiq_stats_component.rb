module Tui
  # Beta 4 — extracted from `Tui::TopStatusBarComponent` (2026-05-21)
  # per "ViewComponents are kings" — sub-elements of the top status
  # bar each get their own VC + spec.
  #
  # Sidekiq queue-depth stats cells: `b<n> e<n> r<n>`. Each cell
  # carries `.sb-sk-cell` plus a state class (`.sk-zero` muted when
  # the count is 0, `.sk-b` / `.sk-e` / `.sk-r` colored when non-zero).
  #
  # Constructor inputs:
  #   - busy:      integer (default 0)
  #   - enqueued:  integer (default 0)
  #   - retry:     integer (default 0) — accepted via kwarg
  #                `retry:` despite being a Ruby keyword (safe in
  #                kwargs context).
  #
  # The `scheduled` count is intentionally NOT rendered here — the
  # bar shows three of the four counts. `scheduled` is a future
  # surface (per-subsystem stack panel).
  #
  # Cells carry `data-tui-status-bar-target="sidekiqBusy"` etc. so
  # `tui_status_bar_controller.js` can patch them in place when the
  # `pito:status_bar` cable pushes new counts.
  class SidekiqStatsComponent < ViewComponent::Base
    def initialize(**kwargs)
      @counts = {
        busy:     kwargs.fetch(:busy, 0).to_i,
        enqueued: kwargs.fetch(:enqueued, 0).to_i,
        retry:    kwargs.fetch(:retry, 0).to_i
      }
    end

    # Letter → count lookup so the template stays a flat list of
    # three cells driven by a single helper.
    def value_for(letter)
      @counts.fetch(letter_to_key(letter), 0)
    end

    def cell_class_for(letter)
      value = value_for(letter)
      return "sb-sk-cell sk-zero" if value.zero?

      "sb-sk-cell sk-#{letter}"
    end

    def target_for(letter)
      case letter.to_s
      when "b" then "sidekiqBusy"
      when "e" then "sidekiqEnqueued"
      when "r" then "sidekiqRetry"
      end
    end

    private

    def letter_to_key(letter)
      case letter.to_s
      when "b" then :busy
      when "e" then :enqueued
      when "r" then :retry
      else letter.to_sym
      end
    end
  end
end
