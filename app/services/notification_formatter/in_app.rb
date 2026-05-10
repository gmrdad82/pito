# Phase 16 §2 — Notification formatter.
#
# In-app structured payload. Returns a hash the §3 ERB views render
# against. The `body_html` slot is HTML-safe — the formatter itself
# converts the `[text](url)` markdown links the templates emit into
# `<a href="">` tags, and runs the result through Rails' `sanitize`
# helper to strip any `<script>` injected via `event_payload`.
#
# Per master decision 2026-05-10 #2: in-app `urgent` severity uses the
# `--color-warn` token (amber) — `--color-error` (red) is reserved
# for genuinely destructive actions per CLAUDE.md.
module NotificationFormatter
  module InApp
    module_function

    # Allow only `<a href="">` tags. The whitelist is intentionally
    # narrow — Spec 02 explicitly limits the in-app markdown subset to
    # `[text](url)` links (master decision #4). Anything else is
    # passed through as text or stripped.
    SANITIZE_TAGS       = %w[a].freeze
    SANITIZE_ATTRIBUTES = %w[href].freeze

    MARKDOWN_LINK_RE = /\[([^\[\]]*)\]\(([^()\s]+)\)/

    def payload_for(notification)
      template = NotificationFormatter.template_for(notification)
      severity = notification.severity.to_s

      {
        title:             template.title.to_s,
        body_html:         render_body_html(template.body.to_s),
        url:               template.url,
        severity:          severity,
        severity_class:    NotificationFormatter::IN_APP_SEVERITY_CLASSES.fetch(severity, "notification-info"),
        glyph:             NotificationFormatter.emoji_for(notification.event_type),
        kind:              notification.event_type.to_s,
        fires_at_relative: NotificationFormatter.format_timestamp(notification.fires_at, :relative),
        fires_at_iso:      NotificationFormatter.format_timestamp(notification.fires_at, :iso),
        read:              notification.read?
      }
    end

    # Convert the template's body string (which may include
    # `[text](url)` markdown) to HTML-safe HTML. Rails' `sanitize`
    # strips `<script>` and any tag/attribute outside the whitelist.
    #
    # Phase 16 §2 security fix-forward (F1 — 2026-05-10 audit). URL
    # scheme allowlist enforced BEFORE the `<a>` tag is written. A
    # `[text](javascript:alert(1))` or `[text](data:text/html,...)` in
    # `event_payload` collapses to bare `text` rather than an empty
    # `<a></a>` shell (which would survive Loofah's `href`-only strip
    # and render as a dead underlined link — see audit F4).
    def render_body_html(text)
      return "".html_safe if text.blank?

      escaped = ERB::Util.html_escape(text.to_s)
      with_links = escaped.gsub(MARKDOWN_LINK_RE) do
        link_text = Regexp.last_match(1)
        link_url  = Regexp.last_match(2)
        if NotificationFormatter.url_scheme_allowed?(link_url)
          # `link_text` is already html_escaped (we ran html_escape on
          # the whole string above). We escape the URL value once more
          # because it sits in an HTML attribute.
          attr_safe_url = ERB::Util.html_escape(link_url)
          %(<a href="#{attr_safe_url}">#{link_text}</a>)
        else
          # Bad-scheme / empty URL — strip the link wrapping, keep the
          # text. `link_text` is already html_escaped.
          link_text
        end
      end

      sanitizer.sanitize(
        with_links,
        tags:       SANITIZE_TAGS,
        attributes: SANITIZE_ATTRIBUTES
      ).html_safe
    end

    def sanitizer
      @sanitizer ||= Rails::Html::SafeListSanitizer.new
    end
  end
end
