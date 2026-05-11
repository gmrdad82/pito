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

  # Phase 7.5 §11c — 14-day rate-limit gate helpers.
  #
  # YouTube limits `title` and `handle` changes to 1 per 14 days
  # server-side. Pito mirrors the gate client-side: when the
  # respective `*_changed_at` timestamp is within the window, the
  # edit form hides the input and renders an explanatory message
  # plus the `[remind me on YYYY-MM-DD]` calendar affordance.
  #
  # The helpers return `false` / `nil` when the column is `nil`
  # (pre-edit state — the field has never been changed via Pito) so
  # the form renders the input freely.
  #
  # Boundary semantics (exactly 14 days):
  #   `title_changed_at == 14.days.ago` is treated as **open**
  #   (gate has just expired). The gate is open only while
  #   `title_changed_at` is **strictly within** the 14-day window.
  def title_gate_open?(channel)
    return false if channel.title_changed_at.blank?

    channel.title_changed_at > 14.days.ago
  end

  def handle_gate_open?(channel)
    return false if channel.handle_changed_at.blank?

    channel.handle_changed_at > 14.days.ago
  end

  # Returns the unlock date as a `YYYY-MM-DD` string, or `nil` when
  # the underlying column is `nil`. The string form is what the
  # `[remind me on YYYY-MM-DD]` bracketed link renders inline; the
  # underlying ISO timestamp goes onto the link via a data attribute
  # so 11h's Stimulus controller can POST it to /calendar/entries.json.
  def title_unlock_date(channel)
    return nil if channel.title_changed_at.blank?

    (channel.title_changed_at + 14.days).to_date.iso8601
  end

  def handle_unlock_date(channel)
    return nil if channel.handle_changed_at.blank?

    (channel.handle_changed_at + 14.days).to_date.iso8601
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

  private

  def em_dash
    "—"
  end
end
