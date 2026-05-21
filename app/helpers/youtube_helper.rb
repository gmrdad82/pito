module YoutubeHelper
  # Brand-account emails come back from Google in the shape
  # `<long-id>@pages.plusgoogle.com`. The domain is noise — every brand
  # account uses it — so we strip the suffix and surface just the local
  # part. Real Gmail (`*@gmail.com`) and custom-domain addresses pass
  # through untouched. View layer only; the model still stores the full
  # email so the value round-trips faithfully if it ever needs to leave
  # the boundary.
  # Delegates to Pito::Formatter::YoutubeConnectionEmail.
  # Strips the brand-account @pages.plusgoogle.com domain noise.
  def format_connection_email(email)
    Pito::Formatter::YoutubeConnectionEmail.call(email)
  end

  # Short, readable label for an OAuth scope. Google scopes arrive as
  # full URLs (`https://www.googleapis.com/auth/userinfo.email`) or as
  # plain strings (`openid`, `email`, `profile`). Strip everything up
  # to and including the last `/` so URL-shaped scopes collapse to the
  # trailing segment; plain strings pass through.
  # Delegates to Pito::Formatter::YoutubeScopeLabel.
  # Strips URL-shaped scopes to the trailing segment; plain strings pass through.
  def format_scope_short_label(scope)
    Pito::Formatter::YoutubeScopeLabel.call(scope)
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

  # Phase 24+ — /channels index URL polish. Build the public
  # `/@handle` form of the YouTube channel URL when a handle is
  # available. Returns nil when the channel has no handle yet
  # (pre-sync or legacy rows); callers fall back to the UC-id URL.
  # The stored `Channel#handle` is the canonical `@xxxx` token
  # (validation enforces the leading `@`), so we feed it straight
  # into the URL after stripping the leading `@`.
  def youtube_at_handle_url(channel)
    handle = channel&.handle.to_s.strip
    return nil if handle.empty?

    slug = handle.start_with?("@") ? handle[1..] : handle
    return nil if slug.empty?

    "https://www.youtube.com/@#{slug}"
  end
end
