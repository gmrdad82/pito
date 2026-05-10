class ChannelDecorator < ApplicationDecorator
  # Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
  # Channel is a thin YouTube-reference record: id, channel_url, star,
  # youtube_connection_id, last_synced_at, timestamps. The JSON surface
  # carries `connected` as a derived "yes" / "no" string (true when
  # youtube_connection_id is set) so external clients (the pito CLI)
  # keep their wire shape stable.
  def as_summary_json
    {
      id: id,
      channel_url: channel_url,
      star: YesNo.to_yes_no(star),
      connected: YesNo.to_yes_no(youtube_connection_id.present?),
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
