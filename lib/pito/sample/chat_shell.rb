# frozen_string_literal: true

# SAMPLE — seed data for first-boot development demo.
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
            kind: :echo,
            payload: { text: "/channels overview", authenticated: true }
          },
          {
            kind: :system,
            payload: { text: "Pulling stats for your 3 active channels…" }
          },
          {
            kind: :enhanced,
            payload: {
              text: "@gmrdad82      1,240      48,310      612h\n@gmrdad82-vlog   890      14,107      188h"
            }
          },

          # --- Second exchange ---
          {
            kind: :echo,
            payload: { text: "/channel @gmrdad82-vlog --detail", authenticated: true }
          },
          {
            kind: :system,
            payload: { text: "Here's the detailed breakdown for @gmrdad82-vlog." }
          },
          {
            kind: :enhanced,
            payload: {
              text: "Subscribers      +47     (2.1%)\nViews            14,107  (+8.3%)\nWatch time       188h    (+5.7%)\nAvg retention    62.4%\nTop video        \"Building a TUI in Rust\" (12.4k views)"
            }
          },

          # --- Third exchange ---
          {
            kind: :echo,
            payload: { text: "/help commands", authenticated: true }
          },
          {
            kind: :system,
            payload: { text: "Here are the commands you can use. Type /help <command> for details." }
          },
          {
            kind: :enhanced,
            payload: {
              text: "/channels       Channel overview & management\n/notifications  View and manage notifications\n/help           Show this help message"
            }
          }
        ]
      end
    end
  end
end
