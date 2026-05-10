# Phase 16 §2 — Notification formatter.
#
# Discord webhook payload builder. One `Notification` row → one
# Discord message: `username: "pito"` + `avatar_url` (when configured)
# + emoji-prefixed `content` line + a single rich embed (title /
# description / color / url / footer / timestamp).
#
# Per Q11: the formatter escapes user-supplied content (notification
# title, body, embedded payload values) using Discord's markdown rules
# before substituting into the embed strings, so a `*bold*` in a video
# title renders as literal `*bold*` rather than rendering bold in the
# Discord client.
module NotificationFormatter
  module Discord
    module_function

    USERNAME = "pito"

    def payload_for(notification)
      template = NotificationFormatter.template_for(notification)
      raw_title = template.title.to_s
      raw_body  = template.body.to_s

      escaped_title = NotificationFormatter.escape_for(raw_title, channel: :discord)
      embed_title   = NotificationFormatter.truncate_for(escaped_title, limit: NotificationFormatter::DISCORD_TITLE_LIMIT)

      embed_description = NotificationFormatter.truncate_for(
        escape_body_preserving_links(raw_body),
        limit: NotificationFormatter::DISCORD_DESCRIPTION_LIMIT
      )

      content = NotificationFormatter.truncate_for(
        "#{NotificationFormatter.emoji_for(notification.event_type)} #{escaped_title}",
        limit: NotificationFormatter::DISCORD_CONTENT_LIMIT
      )

      embed_url = NotificationFormatter.absolute_url(template.url)
      fires_iso = NotificationFormatter.format_timestamp(notification.fires_at, :iso)

      payload = {
        username: USERNAME,
        content: content,
        embeds: [
          {
            title:       embed_title,
            description: embed_description,
            color:       NotificationFormatter.severity_color(notification.severity),
            url:         embed_url,
            footer:      { text: "#{notification.event_type} · #{fires_iso}" },
            timestamp:   fires_iso
          }
        ]
      }

      avatar = NotificationFormatter.avatar_url
      payload[:avatar_url] = avatar if avatar.present?
      payload
    end

    # Body strings emitted by templates may include `[text](url)`
    # markdown links (which we want Discord to render). Discord's
    # markdown also reads `*` / `_` / `~` / `` ` `` etc. as formatting,
    # so we escape those characters but leave the link syntax intact.
    def escape_body_preserving_links(text)
      return "" if text.nil?

      str = text.to_s
      buffer = +""
      i = 0
      len = str.length

      while i < len
        match = str.match(/\[([^\[\]]*)\]\(([^()\s]+)\)/, i)
        if match.nil?
          buffer << NotificationFormatter.escape_for(str[i..], channel: :discord)
          break
        end

        prefix_end = match.begin(0)
        if prefix_end > i
          buffer << NotificationFormatter.escape_for(str[i...prefix_end], channel: :discord)
        end

        link_text = NotificationFormatter.escape_for(match[1], channel: :discord)
        link_url  = match[2]
        buffer << "[#{link_text}](#{link_url})"

        i = match.end(0)
      end

      buffer
    end
  end
end
