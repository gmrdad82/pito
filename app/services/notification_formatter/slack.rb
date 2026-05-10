# Phase 16 §2 — Notification formatter.
#
# Slack webhook payload builder. One `Notification` row → one Slack
# Block Kit message: header (emoji + title), section (mrkdwn body
# with Slack `<url|text>` links), context (event_type · iso).
#
# When the notification has a non-blank URL, the section appends a
# `view in pito` link at the bottom (master decision 2026-05-10 #4).
module NotificationFormatter
  module Slack
    module_function

    USERNAME           = "pito"
    VIEW_LINK_LABEL    = "view in pito"

    # Match `[text](url)` exactly so we can rewrite to Slack's
    # `<url|text>` form.
    MARKDOWN_LINK_RE   = /\[([^\[\]]*)\]\(([^()\s]+)\)/

    def payload_for(notification)
      template = NotificationFormatter.template_for(notification)
      raw_title = template.title.to_s
      raw_body  = template.body.to_s

      header_text = NotificationFormatter.truncate_for(
        "#{NotificationFormatter.emoji_for(notification.event_type)} #{raw_title}",
        limit: NotificationFormatter::SLACK_HEADER_LIMIT
      )

      section_body = body_with_view_link(raw_body, template.url)
      section_text = NotificationFormatter.truncate_for(
        section_body,
        limit: NotificationFormatter::SLACK_SECTION_LIMIT
      )

      fires_iso = NotificationFormatter.format_timestamp(notification.fires_at, :iso)

      payload = {
        username: USERNAME,
        blocks: [
          {
            type: "header",
            text: { type: "plain_text", text: header_text, emoji: true }
          },
          {
            type: "section",
            text: { type: "mrkdwn", text: section_text }
          },
          {
            type: "context",
            elements: [
              {
                type: "mrkdwn",
                text: "#{notification.event_type} · #{fires_iso}"
              }
            ]
          }
        ]
      }

      avatar = NotificationFormatter.avatar_url
      payload[:icon_url] = avatar if avatar.present?
      payload
    end

    # Rewrite Discord-style `[text](url)` markdown links to Slack
    # `<url|text>` syntax + escape the surrounding plain text via
    # Slack's HTML-encoding rules.
    def body_with_view_link(raw_body, url)
      slack_body = rewrite_markdown_links(raw_body)
      absolute   = NotificationFormatter.absolute_url(url)

      if absolute.present?
        # NOTE: VIEW_LINK_LABEL is a fixed literal — we do NOT escape
        # it (it has no special chars) and we do NOT escape the URL
        # itself (URLs are safe in Slack `<url|text>` syntax).
        "#{slack_body}\n\n<#{absolute}|#{VIEW_LINK_LABEL}>"
      else
        slack_body
      end
    end

    def rewrite_markdown_links(text)
      return "" if text.nil?

      str = text.to_s
      buffer = +""
      i = 0
      len = str.length

      while i < len
        match = str.match(MARKDOWN_LINK_RE, i)
        if match.nil?
          buffer << NotificationFormatter.escape_for(str[i..], channel: :slack)
          break
        end

        prefix_end = match.begin(0)
        if prefix_end > i
          buffer << NotificationFormatter.escape_for(str[i...prefix_end], channel: :slack)
        end

        link_text = NotificationFormatter.escape_for(match[1], channel: :slack)
        link_url  = match[2]
        buffer << "<#{link_url}|#{link_text}>"

        i = match.end(0)
      end

      buffer
    end
  end
end
