class ChannelsController < ApplicationController
  def index
    @channels = Channel.left_joins(:videos)
      .select(
        "channels.*",
        "COUNT(videos.id) AS videos_count"
      )
      .group("channels.id")
      .order(title: :asc)
    @max_panes = (AppSetting.get("max_panes") || ENV.fetch("MAX_PANES", 3)).to_i
  end
end
