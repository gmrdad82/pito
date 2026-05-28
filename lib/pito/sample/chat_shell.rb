# frozen_string_literal: true

# SAMPLE — seed data for first-boot demo.
# Each record is a Hash with `kind` (string) and `payload` (Hash) matching
# the Event model's KINDS and the corresponding Pito::Event::*Component's
# expected payload shape.
module Pito
  module Sample
    module ChatShell
      def self.events
        [
          # --- First exchange ---
          {
            kind: "user_message",
            payload: { text: "/channels overview" }
          },
          {
            kind: "assistant_text",
            payload: { text: "Pulling stats for your 3 active channels…" }
          },
          {
            kind: "thought",
            payload: {
              text: "You asked me to provide an overview of your connected channels. I need to fetch subscriber counts, total views, and watch-time data for each one.",
              duration: "4.2s"
            }
          },
          {
            kind: "tool_output",
            payload: {
              title: "# Channel rollup",
              command: "$ pito channels overview --period 7d",
              output: "@gmrdad82      1,240      48,310      612h\n@gmrdad82-vlog   890      14,107      188h"
            }
          },
          {
            kind: "status_footer",
            payload: {
              mode: "Build",
              agent: "Big Pickle",
              duration: "2m 14s"
            }
          },

          # --- Second exchange ---
          {
            kind: "user_message",
            payload: { text: "/channel @gmrdad82-vlog --detail" }
          },
          {
            kind: "assistant_text",
            payload: { text: "Here's the detailed breakdown for @gmrdad82-vlog." }
          },
          {
            kind: "thought",
            payload: {
              text: "Fetching detailed metrics for the vlog channel — subscriber growth, top-performing videos, and audience retention.",
              duration: "3.1s"
            }
          },
          {
            kind: "tool_output",
            payload: {
              title: "# @gmrdad82-vlog — detail",
              command: "$ pito channel @gmrdad82-vlog --detail --period 30d",
              output: "Subscribers      +47     (2.1%)\nViews            14,107  (+8.3%)\nWatch time       188h    (+5.7%)\nAvg retention    62.4%\nTop video        \"Building a TUI in Rust\" (12.4k views)"
            }
          },
          {
            kind: "status_footer",
            payload: {
              mode: "Build",
              agent: "Big Pickle",
              duration: "1m 48s"
            }
          },

          # --- Third exchange ---
          {
            kind: "user_message",
            payload: { text: "/notifications --unread" }
          },
          {
            kind: "thought",
            payload: {
              text: "Checking for unread notifications across all channels and mentions.",
              duration: "0.8s"
            }
          },
          {
            kind: "tool_output",
            payload: {
              title: "# Unread notifications",
              command: "$ pito notifications --unread --limit 5",
              output: "#  Type        Channel           Time         Summary\n1  comment     @gmrdad82         2m ago       \"Great video!\"\n2  milestone   @gmrdad82-vlog    15m ago      1k subscribers!\n3  mention     @gmrdad82         1h ago       @pito in #general\n4  upload      @gmrdad82-vlog    3h ago       \"My new setup\"\n5  alert       @gmrdad82         6h ago       Retention drop on TUI video"
            }
          },
          {
            kind: "status_footer",
            payload: {
              mode: "Inspect",
              agent: "Big Pickle",
              duration: "0.9s"
            }
          },

          # --- Fourth exchange ---
          {
            kind: "user_message",
            payload: { text: "/help commands" }
          },
          {
            kind: "assistant_text",
            payload: { text: "Here are the commands you can use. Type /help <command> for details on any of them." }
          },
          {
            kind: "tool_output",
            payload: {
              title: "# Available commands",
              command: "$ pito help",
              output: "/channels       Channel overview & management\n/notifications  View and manage notifications\n/help           Show this help message\n/settings       Configure pito preferences\n/theme          Switch color themes\n/export         Export channel data"
            }
          }
        ]
      end
    end
  end
end
