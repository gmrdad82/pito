# frozen_string_literal: true

require "cgi"

module Pito
  module Notifications
    # The shared HTML→text engine behind every notification surface, plain or
    # decorated. `Pito::Notifications::WebhookFormatter#convert` calls
    # straight into `.call` to wrap its output in platform bold/bullet
    # markers (Slack `*…*`/`• `, Discord `**…**`/`- `) — this is the ONE strip
    # implementation, not a second regex living next to it.
    #
    # Called with no `bold:`/`bullet:` (the default, both ""), `.call`
    # produces genuinely plain text: <strong>/<b> markers vanish instead of
    # growing asterisks, and <li>/<br>/block-boundary tags still land as
    # newlines so a multi-item sync summary reads as separate lines instead
    # of every word running together. That default is what the two seams
    # that must never leak markup use directly: the FCM push payload
    # (NotificationWebhookDeliverJob#deliver_fcm — a lockscreen has no HTML
    # renderer) and the /notifications.json feed (NotificationsController —
    # pito-tui is a plain terminal). The web drawer keeps using Rails'
    # `sanitize` instead (app/views/notifications/_row.html.erb) since it DOES
    # want the HTML rendered, just safely.
    #
    # Also responsible for scrubbing the private_reminder dedup marker (an
    # HTML comment, `<!-- pito:private_reminder:<date> -->` — see
    # Pito::Notifications::Source::PrivateReminder): its body has no `>`
    # character, so the generic tag-strip pass below removes it whole, same
    # as any other tag, and the final `.strip` drops the space the marker
    # was appended after (`"Finish. <!-- … -->"` → `"Finish."`, not
    # `"Finish. "`).
    module PlainMessage
      module_function

      # Block-level tags whose open OR close marks a line boundary.
      BLOCK_BOUNDARY = %r{</?\s*(?:div|p|ul|ol|h[1-6])\s*/?>}i

      # Best-effort: any failure falls back to the tag-stripped plain text —
      # NEVER raises on real input, since every caller sits on a delivery
      # path (webhook, push, JSON response) that must not blow up on a
      # malformed message.
      def call(message, bold: "", bullet: "")
        text = message.to_s

        # <strong>/<b> → bold markers (both open and close; empty by default).
        text = text.gsub(%r{</?\s*(?:strong|b)\s*>}i, bold)

        # <li> → bullet prefix (empty by default); </li> closes the line.
        text = text.gsub(%r{<\s*li\s*>}i, bullet)
        text = text.gsub(%r{<\s*/\s*li\s*>}i, "\n")

        # <br> and block-element boundaries → newlines.
        text = text.gsub(%r{<\s*br\s*/?\s*>}i, "\n")
        text = text.gsub(BLOCK_BOUNDARY, "\n")

        # Drop any remaining tags — including HTML comments like the
        # private_reminder marker, which match this single-tag pattern whole
        # since they carry no `>` inside their body — then decode entities.
        text = text.gsub(/<[^>]+>/, "")
        text = CGI.unescapeHTML(text)

        # Trim trailing spaces and collapse runs of blank lines.
        text = text.gsub(/[ \t]+\n/, "\n")
        text = text.gsub(/\n{3,}/, "\n\n")
        text.strip
      rescue StandardError
        plain_fallback(message)
      end

      def plain_fallback(message)
        message.to_s.gsub(/<[^>]+>/, "").strip
      rescue StandardError
        message.to_s
      end
      private_class_method :plain_fallback
    end
  end
end
