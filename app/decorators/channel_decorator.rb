class ChannelDecorator < ApplicationDecorator
  # Channel is a thin YouTube-reference record: id, channel_url, star,
  # youtube_connection_id, last_synced_at, timestamps. Every channel
  # is OAuth-linked by definition now; the derived `connected` field
  # was retired alongside the per-channel "is this OAuth-connected?"
  # display surface.
  def as_summary_json
    {
      id: id,
      channel_url: channel_url,
      star: YesNo.to_yes_no(star),
      last_synced_at: last_synced_at&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  def as_detail_json
    as_summary_json.merge(
      video_count: videos.count
    )
  end
end
