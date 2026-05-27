# frozen_string_literal: true

# SAMPLE — this module will be replaced when real data is wired in Plan 2+.
module Pito
  module Sample
    module ChatShell
      # Each record is a Hash with a `kind:` symbol and fields matching the
      # corresponding Pito::Event::*Component constructor arguments.
      def self.events
        [
          # --- First exchange ---
          {
            kind: :user_message,
            body: "/channels overview"
          },
          {
            kind: :assistant_text,
            body: "Pulling stats for your 3 active channels…"
          },
          {
            kind: :thought,
            body: "You asked me to provide an overview of your connected channels. I need to fetch subscriber counts, total views, and watch-time data for each one.",
            duration: "4.2s"
          },
          {
            kind: :tool_output,
            title: "# Channel rollup",
            command: "$ pito channels overview --period 7d",
            output: "@gmrdad82      1,240      48,310      612h\n@gmrdad82-vlog   890      14,107      188h"
          },
          {
            kind: :status_footer,
            mode: "Build",
            agent: "Big Pickle",
            duration: "2m 14s"
          },

          # --- Second exchange ---
          {
            kind: :user_message,
            body: "/channel @gmrdad82-vlog --detail"
          },
          {
            kind: :assistant_text,
            body: "Here's the detailed breakdown for @gmrdad82-vlog."
          },
          {
            kind: :thought,
            body: "Fetching detailed metrics for the vlog channel — subscriber growth, top-performing videos, and audience retention.",
            duration: "3.1s"
          },
          {
            kind: :tool_output,
            title: "# @gmrdad82-vlog — detail",
            command: "$ pito channel @gmrdad82-vlog --detail --period 30d",
            output: "Subscribers      +47     (2.1%)\nViews            14,107  (+8.3%)\nWatch time       188h    (+5.7%)\nAvg retention    62.4%\nTop video        \"Building a TUI in Rust\" (12.4k views)"
          },
          {
            kind: :status_footer,
            mode: "Build",
            agent: "Big Pickle",
            duration: "1m 48s"
          },

          # --- Third exchange ---
          {
            kind: :user_message,
            body: "/notifications --unread"
          },
          {
            kind: :thought,
            body: "Checking for unread notifications across all channels and mentions.",
            duration: "0.8s"
          },
          {
            kind: :tool_output,
            title: "# Unread notifications",
            command: "$ pito notifications --unread --limit 5",
            output: "#  Type        Channel           Time         Summary\n1  comment     @gmrdad82         2m ago       \"Great video!\"\n2  milestone   @gmrdad82-vlog    15m ago      1k subscribers!\n3  mention     @gmrdad82         1h ago       @pito in #general\n4  upload      @gmrdad82-vlog    3h ago       \"My new setup\"\n5  alert       @gmrdad82         6h ago       Retention drop on TUI video"
          },
          {
            kind: :status_footer,
            mode: "Inspect",
            agent: "Big Pickle",
            duration: "0.9s"
          },

          # --- Fourth exchange ---
          {
            kind: :user_message,
            body: "/help commands"
          },
          {
            kind: :assistant_text,
            body: "Here are the commands you can use. Type /help <command> for details on any of them."
          },
          {
            kind: :tool_output,
            title: "# Available commands",
            command: "$ pito help",
            output: "/channels       Channel overview & management\n/notifications  View and manage notifications\n/help           Show this help message\n/settings       Configure pito preferences\n/theme          Switch color themes\n/export         Export channel data"
          }
        ]
      end
    end
  end
end
