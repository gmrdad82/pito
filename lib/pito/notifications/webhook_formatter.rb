# frozen_string_literal: true

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
    # failure falls back to the tag-stripped plain text. The strip/decode/
    # whitespace-cleanup engine itself lives in `Pito::Notifications::
    # PlainMessage` — #convert below just decorates that engine's output
    # with platform bold/bullet markers; see PlainMessage's header for the
    # undecorated sibling used by the FCM and /notifications.json seams.
    module WebhookFormatter
      module_function

      def slack(message)
        convert(message, bold: "*", bullet: "• ")
      end

      def discord(message)
        convert(message, bold: "**", bullet: "- ")
      end

      # Rich, platform-native payloads keyed off the notification's level
      # (emoji + color). Best-effort: any failure falls back to the flat
      # `{ "text" }` / `{ "content" }` plain-text payload so delivery still lands.

      # Slack: a single colored attachment. We use the attachment's `text` field
      # (not nested `blocks`) so Slack renders the `color` as a left border bar on
      # every message — Slack drops that bar when blocks are nested in an attachment.
      def slack_payload(notification)
        style = LevelStyle.style_for(notification.level)
        text  = "#{style[:emoji]} #{slack(notification.message)}".strip
        {
          "attachments" => [
            {
              "color"     => style[:slack],
              "text"      => text,
              "mrkdwn_in" => [ "text" ]
            }
          ]
        }
      rescue StandardError
        { "text" => slack(notification.message) }
      end

      # Discord: a single colored embed with an emoji-prefixed markdown description.
      def discord_payload(notification)
        style = LevelStyle.style_for(notification.level)
        {
          "embeds" => [
            {
              "description" => "#{style[:emoji]} #{discord(notification.message)}".strip,
              "color"       => style[:discord]
            }
          ]
        }
      rescue StandardError
        { "content" => discord(notification.message) }
      end

      # Delegates the actual strip/decode/whitespace-cleanup work to
      # Pito::Notifications::PlainMessage — see that module for why it's the
      # one place this pipeline is implemented, and for its own rescue
      # fallback (matching this file's former plain_fallback exactly, so
      # nothing changes about the "never raise" contract above).
      def convert(message, bold:, bullet:)
        Pito::Notifications::PlainMessage.call(message, bold: bold, bullet: bullet)
      end
      private_class_method :convert
    end
  end
end
