module Tui
  # Beta 4 — Phase 2C (2026-05-22). Wires DateTime through the canonical
  # `Tui::Transitionable` mixin so the per-tick value diff is animated by
  # `tui-transition` (scramble-settle, diff-only — only the chars that
  # changed scramble; unchanged digits + the static colon stay put) and
  # the muted ↔ accent crossfade is driven by an `active_color`.
  #
  # Format shape: `mon may 22 12:34:56` (lowercase weekday + month abbrev).
  # The Ruby `self.format(time)` and the JS `formatNow()` in
  # `tui_date_time_controller.js` MUST agree on this exact shape so the
  # SSR first paint and every subsequent client tick produce a stable
  # diff (otherwise the entire string would scramble on first hydrate).
  #
  # Constructor inputs:
  #   - now: a Time / DateTime — defaults to Time.current. The server
  #          first-paints this; the Stimulus controller takes over at
  #          connect() and pushes new values into the colocated
  #          `tui-transition` outlet at 1Hz.
  #   - future_notifications: integer count of upcoming notifications.
  #          Positive → color flips to :accent (Home section accent).
  #          Zero / negative → color stays :muted.
  #
  # The root span carries both `tui-date-time` (the 1Hz tick driver) and
  # `tui-transition` (the canonical diff-only animator). `tui-date-time`
  # is an outlet host for `tui-transition` so it can call
  # `setValue(...)` and `setColor(...)` on its sibling controller.
  #
  # Pairs with: `Tui::Transitionable`, `tui_transition_controller.js`,
  # `tui_date_time_controller.js`, `Tui::TopStatusBarComponent`.
  class DateTimeComponent < ViewComponent::Base
    include Tui::Transitionable

    WEEKDAYS = %w[sun mon tue wed thu fri sat].freeze
    MONTHS   = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

    def initialize(now: Time.current, future_notifications: 0)
      @now = now
      @future_notifications = future_notifications.to_i
    end

    def current_value
      self.class.format(@now)
    end

    # Canonical format shape. JS mirrors this exactly in `formatNow()`.
    def self.format(time)
      weekday = WEEKDAYS[time.wday]
      month   = MONTHS[time.month - 1]
      hh = Kernel.format("%02d", time.hour)
      mm = Kernel.format("%02d", time.min)
      ss = Kernel.format("%02d", time.sec)
      "#{weekday} #{month} #{time.day} #{hh}:#{mm}:#{ss}"
    end

    def transitionable_data
      transitionable_attrs(
        value: current_value,
        color: notif_color,
        active_color: :accent
      )
    end

    private

    def notif_color
      @future_notifications.positive? ? :accent : :muted
    end
  end
end
