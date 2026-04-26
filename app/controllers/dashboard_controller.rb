class DashboardController < ApplicationController
  def index
    @video_count = Video.count
    @channel_count = Channel.count
  end
end
