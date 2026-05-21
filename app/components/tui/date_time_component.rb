module Tui
  # Beta 4 — extracted from `Tui::TopStatusBarComponent` (2026-05-21)
  # per "ViewComponents are kings" — sub-elements of the top status
  # bar each get their own VC + spec.
  #
  # DateTime cell: `Wed, May 20 · 12:34:56`. The SSR first paint
  # renders an em-dash placeholder (`—`) because the canonical clock
  # is the user's local time, ticked client-side by the cable
  # Stimulus controller at 1Hz. Server time would drift the instant
  # the page loaded.
  #
  # Constructor inputs:
  #   - time: optional Time / DateTime. When present, the SSR paint
  #           formats it as `Wed, May 20 · 12:34:56` (still gets
  #           overwritten by the Stimulus clock the moment the
  #           controller connects). Defaults to nil → renders `—`.
  #
  # The root span carries `data-tui-status-bar-target="clock"` so
  # `tui_status_bar_controller.js#updateClock` patches it in place.
  class DateTimeComponent < ViewComponent::Base
    WEEKDAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze
    MONTHS   = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
    PLACEHOLDER = "—".freeze

    def initialize(time: nil)
      @time = time
    end

    def formatted
      return PLACEHOLDER if @time.nil?

      weekday = WEEKDAYS[@time.wday]
      month   = MONTHS[@time.month - 1]
      hh = format("%02d", @time.hour)
      mm = format("%02d", @time.min)
      ss = format("%02d", @time.sec)
      "#{weekday}, #{month} #{@time.day} · #{hh}:#{mm}:#{ss}"
    end
  end
end
