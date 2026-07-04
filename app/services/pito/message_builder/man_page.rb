# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Shared renderer for nvim/Linux man-page-style help blocks used by all
    # chat-verb `--help` responses.
    #
    # render(usage:, groups:) → html_safe String wrapped in .pito-help-block
    #
    # Format mirrors Game::ListHelp exactly:
    #   - Purple bold section headers (G40 — yellow is reserved for the
    #     actionable/clickable class, headings must not wear it)
    #   - Indented usage line (dim)
    #   - Each group row: "  <cyan token><padding><dim desc>"
    #   - Padding computed from the max raw token width across ALL groups + GAP(3)
    #   - All text html-escaped; result is html_safe
    module ManPage
      module_function

      GAP = 3 # spaces between token column and description column

      # A pre-built, html_safe markup row injected verbatim into the rendered
      # block — the escape hatch for content that must carry live markup (e.g. a
      # Stimulus showcase element) which the escaping `[token, desc]` row path
      # cannot smuggle through. Wrap markup with `ManPage.raw(html)` and drop the
      # result into a group's rows list wherever the raw line should appear.
      Raw = Data.define(:html)

      # @param html [String] html_safe markup emitted verbatim as one block line.
      # @return [Raw]
      def raw(html) = Raw.new(html: html)

      # @param usage  [String]           the usage line (shown indented under "Usage:")
      # @param groups [Array<[String, Array<[String, String]>]>]
      #                                  ordered pairs of [title, [[token, desc], …]]
      # @return [String] html_safe
      def render(usage:, groups:)
        all_rows = groups.flat_map { |_, rows| rows }
        # Raw rows carry pre-built markup, not a [token, desc] pair, so they sit
        # outside the token column and never influence its padding width.
        width    = all_rows.reject { |r| r.is_a?(Raw) }
                           .map { |tok, _| tok.length }.max.to_i + GAP

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
          sorted_rows(rows).each do |entry|
            lines << (entry.is_a?(Raw) ? entry.html : row(entry[0], entry[1], width))
          end
        end

        result = %(<div class="pito-help-block">#{lines.join("\n")}</div>)
        result.html_safe
      end

      # Rows render alphabetically by token (owner 1.0.0 G13 — "easier to
      # follow"), comparing case-insensitively with leading punctuation
      # stripped so `--help` sorts as "help" and `#id` as "id". Groups holding
      # a Raw row keep their authored order — raw markup is dropped "wherever
      # the raw line should appear" and must not be shuffled around.
      def sorted_rows(rows)
        return rows if rows.any? { |r| r.is_a?(Raw) }

        rows.sort_by { |tok, _| tok.downcase.sub(/\A[^a-z0-9]+/, "") }
      end
      private_class_method :sorted_rows

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

      def header(text) = %(<span class="text-purple font-bold">#{esc(text)}</span>)
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
