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
    #
    # == Preview surface vs. details field
    #
    # The same lesson `WebhookDigest` already learned (see that module's
    # header): both platforms' phone notification shades render the embed
    # description (Discord) / attachment text (Slack) VERBATIM — a
    # `<strong>` summary used to land there as literal `**…**`, asterisks and
    # all, instead of bold. The previewed surface now carries only
    # `notification.title` (a plain, Pito::Copy-rendered string every
    # webhook-reaching `Notification.create!` sets), while the
    # platform-flavored `message` rides in a details FIELD instead (Discord
    # embed `fields[0].value`, Slack attachment `fields[0].value`), which
    # neither shade surfaces on the lockscreen. The handful of rows that
    # predate the `title` column (nullable, no backfill) have none — those
    # fall back to previewing the formatted message directly, same as before
    # this fix, since there's nothing plainer to show instead.
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
        {
          "attachments" => [
            {
              "color"     => style[:slack],
              "text"      => preview_text(notification, style[:emoji]),
              "fields"    => slack_details_fields(notification),
              "mrkdwn_in" => [ "text", "fields" ]
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
              "description" => preview_text(notification, style[:emoji]),
              "color"       => style[:discord],
              "fields"      => discord_details_fields(notification)
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

      # See the class doc's "Preview surface vs. details field" — plain,
      # emoji-prefixed `title` when present; the tag-stripped (no bold/bullet
      # markers) message for the pre-title fallback case.
      def preview_text(notification, emoji)
        base = notification.title.presence || convert(notification.message, bold: "", bullet: "")
        "#{emoji} #{base}".strip
      end
      private_class_method :preview_text

      # Empty when there's no `title` to preview instead — in that fallback
      # case `preview_text` already carries the full formatted message, so a
      # details field would just repeat it.
      def slack_details_fields(notification)
        return [] if notification.title.blank?

        [
          {
            "title" => Pito::Copy.render("pito.copy.notifications.webhook_details_label"),
            "value" => slack(notification.message),
            "short" => false
          }
        ]
      end
      private_class_method :slack_details_fields

      def discord_details_fields(notification)
        return [] if notification.title.blank?

        [
          {
            "name"  => Pito::Copy.render("pito.copy.notifications.webhook_details_label"),
            "value" => discord(notification.message)
          }
        ]
      end
      private_class_method :discord_details_fields
    end
  end
end
