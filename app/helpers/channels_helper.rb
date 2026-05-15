module ChannelsHelper
  # Phase 7.5 §11b — channel show page rendering helpers.
  #
  # All four helpers fall back to the muted em-dash placeholder when the
  # underlying column is nil (the pre-sync state — channels created via
  # the OAuth + selection flow start with every metadata column NULL
  # until ChannelSync populates them). The detail pane never 500s on a
  # bare-bones channel.

  # Returns the formatted subscriber count for the analytics row.
  # `hidden_subscriber_count?` wins over the numeric value because the
  # YouTube creator has explicitly chosen to hide the count.
  def formatted_subscriber_count(channel)
    return "Hidden" if channel.hidden_subscriber_count?
    return em_dash if channel.subscriber_count.nil?

    number_with_delimiter(channel.subscriber_count)
  end

  def formatted_view_count(channel)
    return em_dash if channel.view_count.nil?

    number_with_delimiter(channel.view_count)
  end

  def formatted_video_count(channel)
    return em_dash if channel.video_count.nil?

    number_with_delimiter(channel.video_count)
  end

  # H1 display title. Title is nullable until ChannelSync lands the
  # `snippet.title` value from YouTube; before that, render the muted
  # "untitled channel" placeholder so the H1 still reads cleanly.
  def channel_display_title(channel)
    title = channel.title.to_s.strip
    title.empty? ? "untitled channel" : title
  end

  # Renders the channel description as plain text with paragraph and
  # line-break preservation (Rails `simple_format`) plus auto-linking of
  # bare http(s) URLs. The pipeline is:
  #
  #   1. `simple_format` HTML-escapes the input by default and converts
  #      newlines to `<br>` / wraps paragraphs in `<p>`.
  #   2. We then walk the resulting HTML and replace bare URL runs with
  #      `<a href>` anchors. Because step 1 already escaped the raw
  #      input, the URL detector operates on safe text and any `<script>`
  #      or other tag the creator pasted into the description column is
  #      already neutered as literal `&lt;script&gt;`.
  #
  # No Loofah / Sanitize call is needed because `simple_format` with the
  # default `sanitize: true` option runs the input through the same
  # Rails-html-sanitizer pipeline first. The output is `html_safe`.
  AUTO_LINK_URL_REGEX = %r{https?://[^\s<>"']+}
  def channel_description_html(channel)
    text = channel.description.to_s
    return nil if text.strip.empty?

    formatted = simple_format(text, {}, sanitize: true)
    # `simple_format` already HTML-escaped the input — `formatted` is a
    # safe-buffer of `<p>...escaped text...</p>` fragments. We walk that
    # safe text with a URL regex and replace each match with a real
    # `<a>` anchor. The result is reassembled as `html_safe` because
    # both the surrounding text (escaped) and the anchor markup
    # (`link_to`) are already safe.
    auto_linked = formatted.to_s.gsub(AUTO_LINK_URL_REGEX) do |url|
      link_to(url, url, target: "_blank", rel: "noopener noreferrer")
    end
    auto_linked.html_safe
  end

  # Phase 24+ — /channels index URL column. Pick the canonical
  # outbound URL for a channel:
  #   1. `https://www.youtube.com/@<handle>` when handle is populated
  #      (post-sync, the cleaner form most users recognize).
  #   2. `https://www.youtube.com/channel/<UC-id>` (the locked
  #      `channel_url`) otherwise — legacy / pre-sync rows.
  #   3. The raw `channel.channel_url` as a final fallback if the URL
  #      builder cannot extract a UC-id (defense in depth — the model
  #      regex should prevent this on insert, but the view never 500s).
  #
  # Callers render the return value as the row's external link text
  # and href; no truncation — the column is allowed to widen or the
  # row to wrap, depending on table layout.
  def channel_display_url(channel)
    return nil if channel.nil?

    at_handle = youtube_at_handle_url(channel)
    return at_handle if at_handle.present?

    uc_url = youtube_channel_url(channel)
    return uc_url if uc_url.present?

    channel.channel_url
  end

  # 2026-05-11 picker URL column — the visible text for the row's
  # outbound YouTube link. Title moved out of the URL column and now
  # owns the name cell; the URL cell shows only the channel's short
  # identifier:
  #
  #   1. `Channel#handle` (the `@xxxx` form) when present — preferred
  #      because it matches how creators refer to their own channel.
  #   2. The locked `UC<22-char>` slug otherwise — middle-truncated to
  #      `UCxxxxxx…xyz` so legacy / pre-sync rows stay scannable
  #      without flooding the column with a 24-char opaque id.
  #   3. The raw `channel_url` as a final fallback if the UC-id cannot
  #      be extracted (defense in depth; the model regex prevents it
  #      on insert).
  #
  # The href stays the full `channel_display_url(channel)` so the link
  # still resolves to a real YouTube page.
  def channel_url_label(channel)
    return nil if channel.nil?

    handle = channel.handle.to_s.strip
    return handle if handle.present?

    uc_id = youtube_channel_id(channel)
    return middle_truncate(uc_id, head: 6, tail: 3) if uc_id.present?

    channel.channel_url
  end

  private

  def em_dash
    "—"
  end
end
