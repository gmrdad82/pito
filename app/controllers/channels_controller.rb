class ChannelsController < ApplicationController
  def index
    @channels = Channel.left_joins(:videos)
      .select(
        "channels.*",
        "COUNT(videos.id) AS videos_count"
      )
      .group("channels.id")
      .order(title: :asc)
  end
end
