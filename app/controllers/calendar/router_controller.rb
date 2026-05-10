# Phase 15 calendar UX restructure — `/calendar` view-persistence router.
#
# Renders a thin shell that lets the client decide (via localStorage
# `pito-calendar-view`) whether to land on the schedule or the current
# month grid. Fresh visits (no preference, no JS) fall through the
# `<meta http-equiv="refresh">` to the month grid. The Stimulus
# controller `calendar-view-router` runs immediately on page load and
# `window.location.replace`s when a preference is stored — so the
# redirect doesn't grow the browser history.
class Calendar::RouterController < ApplicationController
  def show
    now = Time.current
    @month_path = "/calendar/month/#{now.year}/#{format('%02d', now.month)}"
    @schedule_path = calendar_schedule_path
    render layout: false
  end
end
