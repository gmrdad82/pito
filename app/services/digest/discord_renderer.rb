# Phase 26 — 01e. Discord embeds renderer for the daily digest.
#
# Reads a `Digest::Composer::Result` and returns a Hash POSTable to a
# Discord webhook as JSON. Empty sections are suppressed; "all quiet"
# renders a one-line fallback embed.
#
# Discord webhook reference:
# https://discord.com/developers/docs/resources/webhook#execute-webhook.
# We emit:
#
#   - One top-level `content` carrying the digest title (Discord
#     displays this above the embed; it doubles as the notification
#     preview).
#   - One `embeds[0]` carrying:
#       - `title` — "pito daily digest"
#       - `description` — the rendered window range in the user's
#         local tz, plus the "all quiet" message if applicable.
#       - `fields` — one field per non-empty section. `name` is the
#         section label + total; `value` is a markdown bullet list.
#         Discord caps `value` at 1024 chars; we truncate with a
#         "… and N more" tail.
#       - `timestamp` — ISO 8601, the window end. Discord renders this
#         in the viewer's local tz natively.
#
# Discord allows at most 10 embeds per message + 25 fields per embed +
# 1024 chars per field value. We stay well below all three.
module Digest
  class DiscordRenderer
    FIELD_VALUE_MAX = 1024
    FIELD_TAIL_RESERVE = 64 # leave room for "… and N more" tail

    def initialize(result)
      @result = result
    end

    def call
      {
        "content" => "pito daily digest",
        "embeds" => [ embed ]
      }
    end

    private

    def embed
      base = {
        "title" => "pito daily digest",
        "description" => description,
        "timestamp" => @result.window_ended_at.utc.iso8601
      }

      fields = build_fields
      base["fields"] = fields if fields.any?
      base
    end

    def description
      lines = [ window_label ]
      lines << "no activity in the last 24 hours." unless @result.any_activity?
      lines.join("\n")
    end

    def build_fields
      return [] unless @result.any_activity?

      @result.sections.reject(&:empty?).map do |section|
        {
          "name" => "#{section.label} (#{section.total})",
          "value" => render_value(section),
          "inline" => false
        }
      end
    end

    def render_value(section)
      bullets = section.items.map { |item| "• #{item}" }
      tail =
        if section.total > section.items.size
          "• … and #{section.total - section.items.size} more"
        end

      buf = bullets.join("\n")
      buf = "#{buf}\n#{tail}" if tail

      return buf if buf.length <= FIELD_VALUE_MAX

      # Defensive truncation — long item titles can push us past the
      # 1024 limit. Trim bullets one at a time until we fit.
      truncated = bullets.dup
      while truncated.any?
        truncated.pop
        more = section.total - truncated.size
        candidate = (truncated + [ "• … and #{more} more" ]).join("\n")
        return candidate if candidate.length <= FIELD_VALUE_MAX
      end

      # Worst case: even the trailer is too long. Hard-truncate.
      "• … and #{section.total} more"[0, FIELD_VALUE_MAX]
    end

    def window_label
      tz = @result.user.tz
      starts = @result.window_started_at.in_time_zone(tz)
      ends   = @result.window_ended_at.in_time_zone(tz)
      fmt = "%Y-%m-%d %H:%M %Z"
      "window: #{starts.strftime(fmt)} → #{ends.strftime(fmt)}"
    end
  end
end
