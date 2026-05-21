class DashboardController < ApplicationController
  # Home (/) — intentionally empty during the layout-first rebuild.
  # Panels are added one by one via the demo→pick→implement→confirm flow.
  # See `app/views/dashboard/index.html.erb` for the empty marker.
  #
  # JSON branch retained as the CLI's canonical `get_dashboard` envelope
  # so `pito` deserializes cleanly. Shape: video_count + channel_count +
  # footage_count.

  def index
    respond_to do |format|
      format.html
      format.json { render json: dashboard_json }
    end
  end

  private

  def dashboard_json
    {
      video_count:   Video.count,
      channel_count: Channel.count,
      footage_count: Footage.count
    }
  end
end
