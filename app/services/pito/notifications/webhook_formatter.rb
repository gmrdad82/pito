# frozen_string_literal: true

require "cgi"

module Pito
  module Notifications
    # Converts a Notification#message — which is sometimes HTML (sync
    # summaries: `<strong>…</strong>`, `<ul><li>…</li></ul>`) and sometimes
    # plain text — into platform-flavored markdown for webhook delivery.
    #
    #   * `slack(message)`   → Slack mrkdwn: bold `*…*`, `•` bullets.
    #   * `discord(message)` → Discord markdown: bold `**…**`, `-` bullets.
    #
    # Both are best-effort and MUST NOT raise on real input: any unexpected
    # failure falls back to the tag-stripped plain text.
    module WebhookFormatter
      module_function

      def slack(message)
        convert(message, bold: "*", bullet: "• ")
      end

      def discord(message)
        convert(message, bold: "**", bullet: "- ")
      end

      # Block-level tags whose open OR close marks a line boundary.
      BLOCK_BOUNDARY = %r{</?\s*(?:div|p|ul|ol|h[1-6])\s*/?>}i

      def convert(message, bold:, bullet:)
        text = message.to_s

        # <strong>/<b> → bold markers (both open and close).
        text = text.gsub(%r{</?\s*(?:strong|b)\s*>}i, bold)

        # <li> → bullet prefix; </li> closes the line.
        text = text.gsub(%r{<\s*li\s*>}i, bullet)
        text = text.gsub(%r{<\s*/\s*li\s*>}i, "\n")

        # <br> and block-element boundaries → newlines.
        text = text.gsub(%r{<\s*br\s*/?\s*>}i, "\n")
        text = text.gsub(BLOCK_BOUNDARY, "\n")

        # Drop any remaining tags, then decode HTML entities.
        text = text.gsub(/<[^>]+>/, "")
        text = CGI.unescapeHTML(text)

        # Trim trailing spaces and collapse runs of blank lines.
        text = text.gsub(/[ \t]+\n/, "\n")
        text = text.gsub(/\n{3,}/, "\n\n")
        text.strip
      rescue StandardError
        plain_fallback(message)
      end
      private_class_method :convert

      def plain_fallback(message)
        message.to_s.gsub(/<[^>]+>/, "").strip
      rescue StandardError
        message.to_s
      end
      private_class_method :plain_fallback
    end
  end
end
