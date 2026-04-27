class ChannelsController < ApplicationController
  def index
    @max_panes = max_panes
    @channels = Channel.left_joins(:videos)
      .select(
        "channels.*",
        "COUNT(videos.id) AS videos_count"
      )
      .group("channels.id")
      .order(title: :asc)
  end

  def show
    @channel = Channel.find(params[:id])
    @max_panes = max_panes
    @available_channels = Channel.where.not(id: @channel.id).order(title: :asc)
  end

  def panes
    ids = params[:ids].to_s.split(/[\s,+]+/).reject(&:blank?)

    if ids.size <= 1
      redirect_to ids.first ? channel_path(ids.first) : channels_path
      return
    end

    @max_panes = max_panes
    @current_ids = ids.first(@max_panes)
    @panes = @current_ids.map { |id| Channel.find_by(id: id) }
    @pane_title_length = pane_title_length
    @available_channels = Channel.where.not(id: @current_ids).order(title: :asc) if @panes.compact.size < @max_panes
  end

  private

  def max_panes
    (AppSetting.get("max_panes") || ENV.fetch("MAX_PANES", 3)).to_i
  end

  def pane_title_length
    (AppSetting.get("pane_title_length") || ENV.fetch("PANE_TITLE_LENGTH", 14)).to_i
  end
end
