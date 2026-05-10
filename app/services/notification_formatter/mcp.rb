# Phase 16 §2 — Notification formatter.
#
# MCP plain-markdown payload. Consumed by §3's `notifications_list`
# tool. Plaintext markdown renders in any MCP-host UI without further
# translation.
#
# Per Q11: the formatter backslash-escapes the same markdown control
# set as Discord, then preserves `[text](url)` links verbatim so MCP
# hosts that render markdown produce clickable links.
#
# Per CLAUDE.md external-boundary rule + Q13: `read` is the string
# `"yes"` / `"no"`, NEVER a Boolean.
module NotificationFormatter
  module Mcp
    module_function

    def payload_for(notification)
      template = NotificationFormatter.template_for(notification)

      {
        id:           notification.id.to_s,
        title:        template.title.to_s,
        body_md:      escape_body_preserving_links(template.body.to_s),
        url:          template.url,
        severity:     notification.severity.to_s,
        kind:         notification.event_type.to_s,
        fires_at_iso: NotificationFormatter.format_timestamp(notification.fires_at, :iso),
        read:         notification.read? ? "yes" : "no"
      }
    end

    # Mirrors `Discord#escape_body_preserving_links` but reuses the
    # `:mcp` channel rule (which is the same set as Discord per Q11).
    def escape_body_preserving_links(text)
      return "" if text.nil?

      str = text.to_s
      buffer = +""
      i = 0
      len = str.length

      while i < len
        match = str.match(/\[([^\[\]]*)\]\(([^()\s]+)\)/, i)
        if match.nil?
          buffer << NotificationFormatter.escape_for(str[i..], channel: :mcp)
          break
        end

        prefix_end = match.begin(0)
        if prefix_end > i
          buffer << NotificationFormatter.escape_for(str[i...prefix_end], channel: :mcp)
        end

        link_text = NotificationFormatter.escape_for(match[1], channel: :mcp)
        link_url  = match[2]
        buffer << "[#{link_text}](#{link_url})"

        i = match.end(0)
      end

      buffer
    end
  end
end
