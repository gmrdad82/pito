# frozen_string_literal: true

module Pito
  module Notifications
    # Sends ONE digest message per platform (Slack + Discord) for a batch of
    # same-type notifications, instead of N individual
    # `NotificationWebhookDeliverJob` deliveries. This module only builds the
    # digest payload and posts it — it reuses the exact same delivery
    # mechanism as that job: the `AppSetting` webhook URLs and the
    # `Webhooks::SlackClient` / `Webhooks::DiscordClient` HTTP clients.
    #
    # Layout: neither Slack attachment "fields" nor Discord embed "fields"
    # reliably tabulate two columns, so both platforms get a single
    # monospace, fenced code block with `col1` left-padded to the widest
    # value in the batch, then ` │ `, then `col2`. The color-as-left-border
    # trick is the same one `WebhookFormatter` uses: Slack renders the
    # attachment `color` as a border only when the body lives in the
    # attachment's `text` field (not nested `blocks`); Discord just takes the
    # embed `color`.
    #
    # Best-effort like `WebhookFormatter`: a formatting hiccup never raises —
    # it falls back to a plain (unaligned) text list. A delivery failure on
    # one platform is logged and never blocks the other.
    module WebhookDigest
      module_function

      RELEASES     = { slack: "#5170ff", discord: 0x5170ff }.freeze
      ACHIEVEMENTS = { slack: "#f59e0b", discord: 0xf59e0b }.freeze

      COLUMN_SEPARATOR = " │ "

      # `title`  — String header, e.g. "🎮 Upcoming releases".
      # `accent` — Hash `{ slack: "#RRGGBB", discord: 0xRRGGBB }` (see
      #            `RELEASES` / `ACHIEVEMENTS`).
      # `rows`   — Array of `[col1, col2]` String pairs. Empty (or nil) →
      #            no-op: no empty digest is ever sent.
      def call(title:, accent:, rows:)
        return if rows.blank?

        deliver_slack(title, accent, rows)
        deliver_discord(title, accent, rows)
      end

      def deliver(title:, accent:, rows:)
        call(title: title, accent: accent, rows: rows)
      end

      def deliver_slack(title, accent, rows)
        url = AppSetting.slack_webhook_url
        return if url.blank?

        payload = slack_payload(title, accent, rows)
        result  = Webhooks::SlackClient.new(url).deliver(payload)
        return if result.success?

        Rails.logger.warn("[WebhookDigest] Slack delivery failed: #{result.error}")
      rescue StandardError => e
        Rails.logger.warn("[WebhookDigest] Slack delivery error: #{e.class}: #{e.message}")
      end

      def deliver_discord(title, accent, rows)
        url = AppSetting.discord_webhook_url
        return if url.blank?

        payload = discord_payload(title, accent, rows)
        result  = Webhooks::DiscordClient.new(url).deliver(payload)
        return if result.success?

        Rails.logger.warn("[WebhookDigest] Discord delivery failed: #{result.error}")
      rescue StandardError => e
        Rails.logger.warn("[WebhookDigest] Discord delivery error: #{e.class}: #{e.message}")
      end

      # Slack: a single colored attachment. Same trick as
      # `WebhookFormatter.slack_payload` — the body lives in the
      # attachment's `text` (not nested `blocks`) so Slack renders `color`
      # as a left border bar.
      def slack_payload(title, accent, rows)
        {
          "attachments" => [
            {
              "color"     => accent[:slack],
              "text"      => "#{title}\n#{table(rows)}",
              "mrkdwn_in" => [ "text" ]
            }
          ]
        }
      rescue StandardError
        { "text" => "#{title}\n#{plain_list(rows)}" }
      end

      # Discord: a single colored embed with the digest title as the embed
      # title and the aligned table as its description.
      def discord_payload(title, accent, rows)
        {
          "embeds" => [
            {
              "title"       => title,
              "description" => table(rows),
              "color"       => accent[:discord]
            }
          ]
        }
      rescue StandardError
        { "content" => "#{title}\n#{plain_list(rows)}" }
      end

      # Fenced code block, one row per line, `col1` left-padded to the
      # widest value in the batch so `col2` lines up across every row —
      # the only 2-column layout that survives both Slack and Discord's
      # markdown renderers.
      def table(rows)
        width = rows.map { |col1, _| col1.to_s.length }.max.to_i
        lines = rows.map { |col1, col2| "#{col1.to_s.ljust(width)}#{COLUMN_SEPARATOR}#{col2}" }
        "```\n#{lines.join("\n")}\n```"
      end

      # Fallback used when `table` (or payload assembly) raises: an
      # unaligned but still readable text list.
      def plain_list(rows)
        rows.map { |col1, col2| "#{col1} - #{col2}" }.join("\n")
      end

      private_class_method :deliver_slack, :deliver_discord, :slack_payload, :discord_payload, :table, :plain_list
    end
  end
end
