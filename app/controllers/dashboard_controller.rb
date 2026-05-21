class DashboardController < ApplicationController
  # Chart-sweep dispatch (2026-05-07). The dashboard charts (daily views,
  # views by channel, daily engagement) have been retired as a coordinated
  # cross-stack reset. The page is intentionally a near-empty placeholder
  # until intentional metrics arrive in a later phase. The JSON branch
  # collapses to summary counts only — the count shape mirrors the
  # MCP `get_dashboard` tool exactly so the pito CLI's
  # `DashboardData` struct deserializes cleanly.
  #
  # D18 (2026-05-21) — Projects dropped; project_count removed from
  # the JSON envelope.
  def index
    @video_count = Video.count
    @channel_count = Channel.count

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
      video_count: @video_count,
      channel_count: @channel_count,
      footage_count: @footage_count
    }
  end
end
