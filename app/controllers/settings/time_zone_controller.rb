# Phase 26 — 01a. Timezone foundation.
#
# Single `update` endpoint for the authenticated user's `time_zone`.
# Two callers:
#
#   1. The Stimulus `timezone-detect` controller, mounted on `<body>`
#      on every authenticated page. On first load (when the user's
#      stored zone is still `"Etc/UTC"` — the "never set" sentinel)
#      it POSTs the browser-detected zone from
#      `Intl.DateTimeFormat().resolvedOptions().timeZone`. Silent
#      success: 204 on persist, 422 on validation failure (the JS
#      ignores the response either way — silent failure is fine).
#
#   2. The Settings page dropdown (`_time_zone_pane.html.erb`).
#      Normal form submit; success redirects back to `/settings`
#      with a flash notice.
#
# Both callers hit the same `time_zone` param shape. The controller
# distinguishes the two by `request.format` — HTML for the form,
# anything else (including the default Stimulus fetch) for the JS
# branch.
class Settings::TimeZoneController < ApplicationController
  def update
    new_tz = params[:time_zone].to_s

    if Current.user.update(time_zone: new_tz)
      respond_to do |format|
        format.html { redirect_to settings_path, notice: "time zone saved." }
        format.any  { head :no_content }
      end
    else
      message = Current.user.errors[:time_zone].first || "invalid time zone"
      respond_to do |format|
        format.html { redirect_to settings_path, alert: message }
        format.any  { render plain: message, status: :unprocessable_content }
      end
    end
  end
end
