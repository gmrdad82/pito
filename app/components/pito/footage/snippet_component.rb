# frozen_string_literal: true

module Pito
  module Footage
    # Renders a copyable shell one-liner the user runs inside their footage
    # folder. The command ffprobes every file in the CURRENT folder (-maxdepth 1),
    # rounds EACH file's duration UP to the next 0.5 hour, sums them, prints the
    # 1-decimal total, and copies it via `wl-copy` when available. The user then
    # pastes that number into `footage update <id> <hours>`.
    #
    # Wired to the shared `pito--clipboard` Stimulus controller: clicking the copy
    # affordance writes COMMAND to the clipboard and flips the feedback target to
    # "Copied!".
    class SnippetComponent < ViewComponent::Base
      # The exact shell script, formatted as a readable multi-line command with `\`
      # line continuations (owner 2026-07-01: read pro, not a wrapped one-liner).
      # Single-quoted heredoc → no interpolation and no escaping of the embedded
      # quotes/braces/parens. `.chomp` drops the trailing newline. It copies + pastes
      # as-is (backslash-newline continuations are valid bash).
      #
      # int(($1+1799)/1800) ceils each file's seconds to half-hour units; s/2 is
      # the total in hours with one decimal.
      COMMAND = <<~'CMD'.chomp.freeze
        h=$(find . -maxdepth 1 -type f -print0 \
          | xargs -0 -I{} ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 {} 2>/dev/null \
          | awk '{s+=int(($1+1799)/1800)} END{printf "%.1f", s/2}')
        echo "$h"
        command -v wl-copy >/dev/null && printf %s "$h" | wl-copy
      CMD

      def command
        COMMAND
      end

      def hint
        I18n.t("pito.footage.snippet.hint")
      end

      def copy_label
        I18n.t("pito.footage.snippet.copy_label")
      end

      def aria_label
        I18n.t("pito.footage.snippet.aria_label")
      end
    end
  end
end
