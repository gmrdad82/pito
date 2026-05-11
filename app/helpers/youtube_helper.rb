module YoutubeHelper
  # Brand-account emails come back from Google in the shape
  # `<long-id>@pages.plusgoogle.com`. The domain is noise — every brand
  # account uses it — so we strip the suffix and surface just the local
  # part. Real Gmail (`*@gmail.com`) and custom-domain addresses pass
  # through untouched. View layer only; the model still stores the full
  # email so the value round-trips faithfully if it ever needs to leave
  # the boundary.
  def format_connection_email(email)
    str = email.to_s
    return str if str.empty?

    local, domain = str.split("@", 2)
    return str if domain.nil?

    if domain.casecmp("pages.plusgoogle.com").zero?
      local
    else
      str
    end
  end

  # Short, readable label for an OAuth scope. Google scopes arrive as
  # full URLs (`https://www.googleapis.com/auth/userinfo.email`) or as
  # plain strings (`openid`, `email`, `profile`). Strip everything up
  # to and including the last `/` so URL-shaped scopes collapse to the
  # trailing segment; plain strings pass through.
  def format_scope_short_label(scope)
    str = scope.to_s
    return "" if str.empty?

    str.include?("/") ? str.split("/").last.to_s : str
  end

  # Phase 7.5 §11b — outbound URL builders for the channel show page.
  #
  # The channel's locked `channel_url` is itself a YouTube URL of the
  # shape `https://www.youtube.com/channel/<UC-id>` (enforced by
  # `Channel::CHANNEL_URL_REGEX`). We extract the UC-id and use it to
  # build both the standard YouTube channel page link and the YouTube
  # Studio editor link. Defense in depth: if the URL is malformed
  # somehow (it shouldn't be — the model regex prevents it on insert),
  # the extractor returns nil and the URL builders return nil so the
  # view can skip rendering the link rather than emit a broken href.

  YOUTUBE_CHANNEL_URL_ID_REGEX = %r{/channel/(UC[A-Za-z0-9_-]{22})}

  def youtube_channel_id(channel)
    url = channel&.channel_url.to_s
    match = url.match(YOUTUBE_CHANNEL_URL_ID_REGEX)
    match && match[1]
  end

  def youtube_channel_url(channel)
    id = youtube_channel_id(channel)
    return nil if id.nil?

    "https://www.youtube.com/channel/#{id}"
  end

  def youtube_studio_url(channel)
    id = youtube_channel_id(channel)
    return nil if id.nil?

    "https://studio.youtube.com/channel/#{id}"
  end
end
