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
    # == Preview surface vs. details field
    #
    # Both platforms' phone notification shades render the embed description
    # (Discord) / attachment text (Slack) VERBATIM, fenced code block and
    # all — a batch of achievements used to preview as raw
    # "``` \nFirst Light │ TEKKEN 7…" noise. So the previewed surface now
    # carries only `summary_line` (a plain "count: leading-column list"
    # sentence, no backticks) and the aligned table rides in a FIELD instead
    # (Discord embed `fields[0].value`, Slack attachment `fields[0].value`) —
    # neither shade renders field values, so the rich in-app table survives
    # untouched while the phone preview stays clean on both platforms.
    #
    # Layout: neither Slack attachment "fields" nor Discord embed "fields"
    # reliably tabulate two columns, so the table itself is still a single
    # monospace, fenced code block with `col1` left-padded to the widest
    # value in the batch, then ` │ `, then `col2` — same shape as before,
    # just relocated out of the previewed surface. The color-as-left-border
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

      # Preview-surface list cap — `summary_line` shows at most this many
      # leading-column values before collapsing the rest into "+N more", so
      # one giant batch still previews as a single readable line.
      SUMMARY_LIST_LIMIT = 5

      # Discord hard cap on an embed field's `value` (characters). The Slack
      # field carries the same table with no cap — Slack has no documented
      # equivalent limit as tight as this.
      DISCORD_FIELD_VALUE_LIMIT = 1024

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
      # as a left border bar. `text` (the previewed surface — see the class
      # doc's "Preview surface vs. details field") carries only the clean
      # `summary_line`; the fenced table moves to a `fields` entry, which
      # Slack mobile's notification preview does not surface.
      def slack_payload(title, accent, rows)
        {
          "attachments" => [
            {
              "color"     => accent[:slack],
              "text"      => "#{title}\n#{summary_line(rows)}",
              "fields"    => [
                {
                  "title" => Pito::Copy.render("pito.copy.notifications.webhook_digest_details_label"),
                  "value" => table(rows),
                  "short" => false
                }
              ],
              "mrkdwn_in" => [ "text", "fields" ]
            }
          ]
        }
      rescue StandardError
        { "text" => "#{title}\n#{plain_list(rows)}" }
      end

      # Discord: a single colored embed with the digest title as the embed
      # title, the clean `summary_line` as its description (the previewed
      # surface — see the class doc's "Preview surface vs. details field"),
      # and the fenced table in a `fields` entry instead, capped to
      # `DISCORD_FIELD_VALUE_LIMIT` — a field value, unlike the description,
      # never reaches the notification shade.
      def discord_payload(title, accent, rows)
        {
          "embeds" => [
            {
              "title"       => title,
              "description" => summary_line(rows),
              "color"       => accent[:discord],
              "fields"      => [
                {
                  "name"  => Pito::Copy.render("pito.copy.notifications.webhook_digest_details_label"),
                  "value" => table(rows, max_chars: DISCORD_FIELD_VALUE_LIMIT)
                }
              ]
            }
          ]
        }
      rescue StandardError
        { "content" => "#{title}\n#{plain_list(rows)}" }
      end

      # Plain, shade-safe preview line: "<count>: <capped, comma-joined
      # leading-column list>" — no backticks, no alignment, reads fine for
      # any digest title (renders through `Pito::Copy` so it stays
      # translatable and covers both callers without a per-caller phrasing
      # param; see `pito.copy.notifications.webhook_digest_summary`).
      def summary_line(rows)
        Pito::Copy.render(
          "pito.copy.notifications.webhook_digest_summary",
          count: rows.size,
          list:  summary_list(rows)
        )
      end

      # Comma-joined `col1` values, capped at `SUMMARY_LIST_LIMIT` with a
      # "+N more" tail once the batch runs long.
      def summary_list(rows)
        labels = rows.map { |col1, _| col1.to_s }
        return labels.join(", ") if labels.size <= SUMMARY_LIST_LIMIT

        visible = labels.first(SUMMARY_LIST_LIMIT)
        "#{visible.join(", ")}, +#{labels.size - SUMMARY_LIST_LIMIT} more"
      end

      # Fenced code block, one row per line, `col1` left-padded to the
      # widest value in the batch so `col2` lines up across every row —
      # the only 2-column layout that survives both Slack and Discord's
      # markdown renderers. `max_chars`, when given, drops trailing rows
      # (replacing them with a "+N more" line, still inside the fence) until
      # the block fits — Discord rejects an embed field `value` over
      # `DISCORD_FIELD_VALUE_LIMIT` chars outright, so overflowing there is
      # not an option.
      def table(rows, max_chars: nil)
        width = rows.map { |col1, _| col1.to_s.length }.max.to_i
        lines = rows.map { |col1, col2| "#{col1.to_s.ljust(width)}#{COLUMN_SEPARATOR}#{col2}" }
        fenced = "```\n#{lines.join("\n")}\n```"
        return fenced if max_chars.nil? || fenced.length <= max_chars

        truncate_table(lines, max_chars)
      end

      # Drops rows from the end of `lines`, one at a time, appending a
      # "+N more" line inside the fence, until the fenced block fits within
      # `max_chars` (or there are no rows left to drop).
      def truncate_table(lines, max_chars)
        kept = lines.dup

        loop do
          hidden = lines.size - kept.size
          body   = hidden.zero? ? kept : kept + [ "+#{hidden} more" ]
          fenced = "```\n#{body.join("\n")}\n```"
          return fenced if fenced.length <= max_chars || kept.empty?

          kept.pop
        end
      end

      # Fallback used when `table` (or payload assembly) raises: an
      # unaligned but still readable text list.
      def plain_list(rows)
        rows.map { |col1, col2| "#{col1} - #{col2}" }.join("\n")
      end

      private_class_method :deliver_slack, :deliver_discord, :slack_payload, :discord_payload,
                            :summary_line, :summary_list, :table, :truncate_table, :plain_list
    end
  end
end
