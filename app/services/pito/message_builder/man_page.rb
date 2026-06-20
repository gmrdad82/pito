# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Shared renderer for nvim/Linux man-page-style help blocks used by all
    # chat-verb `--help` responses.
    #
    # render(usage:, groups:) → html_safe String wrapped in .pito-help-block
    #
    # Format mirrors Game::ListHelp exactly:
    #   - Yellow bold section headers
    #   - Indented usage line (dim)
    #   - Each group row: "  <cyan token><padding><dim desc>"
    #   - Padding computed from the max raw token width across ALL groups + GAP(3)
    #   - All text html-escaped; result is html_safe
    module ManPage
      module_function

      GAP = 3 # spaces between token column and description column

      # @param usage  [String]           the usage line (shown indented under "Usage:")
      # @param groups [Array<[String, Array<[String, String]>]>]
      #                                  ordered pairs of [title, [[token, desc], …]]
      # @return [String] html_safe
      def render(usage:, groups:)
        all_rows = groups.flat_map { |_, rows| rows }
        width    = all_rows.map { |tok, _| tok.length }.max.to_i + GAP

        lines = []
        # Lead the first line with the inline timestamp slot so the message's
        # "HH:MM ·" prefix lands INSIDE the help block (a white-space: pre-wrap
        # block div) rather than orphaned on its own line above it. When the
        # message carries no timestamp, BodyComponent removes the empty slot.
        lines << "#{Pito::Event::BodyComponent::TS_SLOT}#{header("Usage:")}"
        lines << "  #{dim(esc(usage))}"

        groups.each do |title, rows|
          lines << ""
          lines << header(title)
          rows.each { |tok, desc| lines << row(tok, desc, width) }
        end

        result = %(<div class="pito-help-block">#{lines.join("\n")}</div>)
        result.html_safe
      end

      # ── Helpers (private to module) ──────────────────────────────────────────

      # A description may carry embedded newlines to render as a stacked list
      # (e.g. the schedule `<when>` forms). The first segment sits on the token
      # row; each continuation line is indented to the description column so the
      # list aligns under the first segment instead of wrapping to the margin.
      def row(token, desc, width)
        pad           = " " * (width - token.length)
        first, *rest  = desc.split("\n")
        line          = "  #{cyan(esc(token))}#{pad}#{dim(esc(first))}"
        return line if rest.empty?

        indent = " " * (2 + width) # leading "  " + token column
        ([ line ] + rest.map { |seg| "#{indent}#{dim(esc(seg))}" }).join("\n")
      end
      private_class_method :row

      def header(text) = %(<span class="text-yellow font-bold">#{esc(text)}</span>)
      private_class_method :header

      def cyan(html)   = %(<span class="text-cyan">#{html}</span>)
      private_class_method :cyan

      def dim(html)    = %(<span class="text-fg-dim">#{html}</span>)
      private_class_method :dim

      def esc(text)    = ERB::Util.html_escape(text)
      private_class_method :esc
    end
  end
end
