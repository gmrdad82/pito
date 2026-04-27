class ChannelDecorator < ApplicationDecorator
  def formatted_subscriber_count
    formatted_number(subscriber_count)
  end

  def formatted_view_count
    formatted_number(view_count)
  end

  def formatted_video_count
    formatted_number(video_count)
  end

  def as_summary_json
    {
      id: id,
      youtube_channel_id: youtube_channel_id,
      title: title,
      connected: connected?,
      subscriber_count: subscriber_count || 0,
      video_count: video_count || 0,
      view_count: view_count || 0
    }
  end

  def as_detail_json
    as_summary_json.merge(
      description: description,
      thumbnail_url: thumbnail_url,
      last_synced_at: last_synced_at&.iso8601,
      videos: videos.map { |v| VideoDecorator.new(v).as_summary_json }
    )
  end
end
