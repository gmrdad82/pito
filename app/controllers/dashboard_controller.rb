class DashboardController < ApplicationController
  # Chart-sweep dispatch (2026-05-07). The dashboard charts (daily views,
  # views by channel, daily engagement) have been retired as a coordinated
  # cross-stack reset. The JSON branch collapses to summary counts only —
  # the count shape mirrors the MCP `get_dashboard` tool exactly so the
  # pito CLI's `DashboardData` struct deserializes cleanly.
  #
  # D18 (2026-05-21) — Projects dropped; project_count removed from
  # the JSON envelope.
  #
  # C18 (2026-05-21) — /settings consolidated into /. The ex-settings
  # panels (security, notifications, stack, time_zone) now render from
  # this action. Stack-data assembly lives in Pito::Home::DashboardPayload.

  def index
    @video_count   = Video.count
    @channel_count = Channel.count

    Pito::Home::DashboardPayload.new(user: Current.user, params: params).call
      .each { |key, value| instance_variable_set(:"@#{key}", value) }

    respond_to do |format|
      format.html
      format.json do
        @footage_count = Footage.count
        render json: dashboard_json
      end
    end
  end

  private

  def dashboard_json
    {
      video_count:   @video_count,
      channel_count: @channel_count,
      footage_count: @footage_count
    }
  end
end
