# Slack Block Kit renderer for the daily digest.
#
# Reads a `Digest::Composer::Result` and returns a Hash POSTable to a
# Slack incoming webhook as JSON. Empty sections are suppressed
# (`Composer::Section#empty?`). The "all quiet" case (no sections with
# any activity) renders a one-line `section` block.
#
# Block Kit reference: https://api.slack.com/block-kit. We emit:
#
#   - One `header` block for the digest title.
#   - One `context` block carrying the rendered window range in the
#     user's local tz.
#   - One `section` per non-empty `Composer::Section`. Each section
#     uses a `mrkdwn` text field with a bold label + a bullet list.
#   - `divider` blocks between sections so the message reads cleanly
#     in the Slack client.
#
# The wire field shape is `{ "text": <fallback>, "blocks": [...] }`.
# `text` is the plaintext fallback for notification previews + screen
# readers — required by Slack when `blocks` is present.
module Digest
  class SlackRenderer
    def initialize(result)
      @result = result
    end

    def call
      {
        "text" => fallback_text,
        "blocks" => blocks
      }
    end

    private

    def blocks
      out = [ header_block, context_block ]

      if @result.any_activity?
        @result.sections.reject(&:empty?).each_with_index do |section, idx|
          out << { "type" => "divider" } if idx.positive?
          out << section_block(section)
        end
      else
        out << { "type" => "divider" }
        out << {
          "type" => "section",
          "text" => {
            "type" => "mrkdwn",
            "text" => "no activity in the last 24 hours."
          }
        }
      end

      out
    end

    def header_block
      {
        "type" => "header",
        "text" => {
          "type" => "plain_text",
          "text" => "pito daily digest"
        }
      }
    end

    def context_block
      {
        "type" => "context",
        "elements" => [
          {
            "type" => "mrkdwn",
            "text" => window_label
          }
        ]
      }
    end

    def section_block(section)
      lines = [ "*#{section.label}* (#{section.total})" ]
      section.items.each { |item| lines << "  • #{item}" }
      if section.total > section.items.size
        lines << "  • … and #{section.total - section.items.size} more"
      end

      {
        "type" => "section",
        "text" => {
          "type" => "mrkdwn",
          "text" => lines.join("\n")
        }
      }
    end

    def fallback_text
      if @result.any_activity?
        active = @result.sections.reject(&:empty?)
        "pito daily digest — #{active.map { |s| "#{s.total} #{s.label}" }.join(', ')}"
      else
        "pito daily digest — no activity in the last 24 hours."
      end
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
