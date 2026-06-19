# Notification formatter.
#
# Slack webhook payload builder. One `Notification` row → one Slack
# Block Kit message: header (emoji + title), section (mrkdwn body
# with Slack `<url|text>` links), context (event_type · iso).
#
# When the notification has a non-blank URL, the section appends a
# `view in pito` link at the bottom (master decision 2026-05-10 #4).
module Pito
  module Notifications
    module Formatter
      module Slack
        module_function

        USERNAME           = "pito"
        VIEW_LINK_LABEL    = "view in pito"

        # Match `[text](url)` exactly so we can rewrite to Slack's
        # `<url|text>` form.
        MARKDOWN_LINK_RE   = /\[([^\[\]]*)\]\(([^()\s]+)\)/

        def payload_for(notification)
          template = Pito::Notifications::Formatter.template_for(notification)
          raw_title = template.title.to_s
          raw_body  = template.body.to_s

          header_text = Pito::Notifications::Formatter.truncate_for(
            "#{Pito::Notifications::Formatter.emoji_for(notification.event_type)} #{raw_title}",
            limit: Pito::Notifications::Formatter::SLACK_HEADER_LIMIT
          )

          section_body = body_with_view_link(raw_body, template.url)
          section_text = Pito::Notifications::Formatter.truncate_for(
            section_body,
            limit: Pito::Notifications::Formatter::SLACK_SECTION_LIMIT
          )

          fires_iso = Pito::Notifications::Formatter.format_timestamp(notification.fires_at, :iso)

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

          avatar = Pito::Notifications::Formatter.avatar_url
          payload[:icon_url] = avatar if avatar.present?
          payload
        end

        # Rewrite Discord-style `[text](url)` markdown links to Slack
        # `<url|text>` syntax + escape the surrounding plain text via
        # Slack's HTML-encoding rules.
        def body_with_view_link(raw_body, url)
          slack_body = rewrite_markdown_links(raw_body)
          absolute   = Pito::Notifications::Formatter.absolute_url(url)

          if absolute.present?
            "#{slack_body}\n\n<#{absolute}|#{VIEW_LINK_LABEL}>"
          else
            slack_body
          end
        end

        # Security fix-forward. URL scheme allowlist applied at the markdown boundary.
        def rewrite_markdown_links(text)
          return "" if text.nil?

          str = text.to_s
          buffer = +""
          i = 0
          len = str.length

          while i < len
            match = str.match(MARKDOWN_LINK_RE, i)
            if match.nil?
              buffer << Pito::Notifications::Formatter.escape_for(str[i..], channel: :slack)
              break
            end

            prefix_end = match.begin(0)
            if prefix_end > i
              buffer << Pito::Notifications::Formatter.escape_for(str[i...prefix_end], channel: :slack)
            end

            link_text = Pito::Notifications::Formatter.escape_for(match[1], channel: :slack)
            link_url  = match[2]
            if Pito::Notifications::Formatter.url_scheme_allowed?(link_url)
              buffer << "<#{link_url}|#{link_text}>"
            else
              buffer << link_text
            end

            i = match.end(0)
          end

          buffer
        end
      end
    end
  end
end
