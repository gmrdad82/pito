# frozen_string_literal: true

module Pito
  module Mcp
    # The LLM-readable face of a scrollback event array — EventJson's text sibling.
    # Non-browser MCP clients (claude.ai, ChatGPT connectors) can't read HTML, hex
    # colors, or reply handles, so this projects the structured jsonb payload into
    # GitHub-flavoured markdown / plain text:
    #
    #   * `table_rows`  → a markdown table (list / linked-videos / channel-videos)
    #   * `bars`        → labelled percentage lists (analyze breakdowns)
    #   * `games`       → a bullet list (a channel's games grid)
    #   * `text`        → verbatim (already-rendered copy)
    #   * `body` (HTML) → de-HTML'd, block-aware, entity-decoded (detail cards,
    #                     shinies, similar-games, analytics intros — everything whose
    #                     content lives only in the rendered ViewComponent HTML)
    #
    # Analytics SCALAR VALUES are not persisted in the payload (the glance marker
    # carries only `metric_keys`; the analyze `scaffold` is 0/1 pulled-flags). The
    # Executor computes them inline and fills a canonical `metrics` shape,
    # which this projects as `label: value` lines — see #metrics_lines.
    #
    # PURE READ + PURE FUNCTION: no DB, no persistence, no mutation. Payload keys are
    # read with indifferent access because a Router Result carries PRE-jsonb payloads
    # whose keys are a mix of String (top level) and Symbol (`table_rows` cells).
    module EventText
      module_function

      # Project an events array (each `{ kind:, payload: }`) into one markdown string.
      # Blank per-event projections are dropped; the rest are blank-line separated.
      def call(events)
        Array(events)
          .filter_map { |event| project(indifferent(event_payload(event))) }
          .reject(&:blank?)
          .join("\n\n")
      end

      # ── per-event dispatch ─────────────────────────────────────────────────────

      # Pick the projection by payload STRUCTURE, not event kind — a Router Result
      # carries pre-canonical kinds (several `:system`), so kind is unreliable.
      def project(payload)
        return nil if payload.blank?
        # Error events (Finalizer.result_events → {message_key, message_args}) carry
        # no rendered copy — render it here, the way EventJson does for JSON clients.
        return copy_text(payload) if payload[:message_key].present? && payload[:text].blank?

        parts = [ intro(payload) ]
        parts << payload[:text].to_s                    if payload[:text].present?   # heading / prose
        parts << metrics_lines(payload[:metrics])       if payload[:metrics].present?
        parts << markdown_table(payload)                if payload[:table_rows].present?
        parts << breakdown_lists(payload[:bars], payload[:bar_captions]) if payload[:bars].present?
        parts << games_list(payload[:games])            if payload[:games].present?

        body = parts.compact.reject(&:blank?)
        # Nothing structured surfaced → fall back to the de-HTML'd body copy.
        return html_to_text(payload[:body]) if body.empty?

        body.join("\n\n")
      end

      # The leading prose of a structured event (the list/analyze intro) — de-HTML'd,
      # kept only when the event ALSO has structured content (else the body IS the
      # projection and #project handles it in the fallback).
      def intro(payload)
        return nil unless structured?(payload)

        html_to_text(payload[:body])
      end

      def structured?(payload)
        payload[:table_rows].present? || payload[:bars].present? ||
          payload[:games].present? || payload[:metrics].present?
      end

      # ── markdown table (table_rows → GitHub markdown) ──────────────────────────

      # `table_heading` is Array<String | {text:, class:}>; `table_rows` is
      # Array<{ cells: Array<{text:, html:}> }>. Cells marked html: true carry markup
      # in `text`, so every cell is inline-stripped. Pipes are escaped.
      def markdown_table(payload)
        headers = Array(payload[:table_heading]).map { |h| heading_text(h) }
        rows    = Array(payload[:table_rows]).map do |row|
          Array(row[:cells]).map { |cell| cell_text(cell) }
        end
        return "" if rows.empty?

        width   = ([ headers.size ] + rows.map(&:size)).max
        headers = pad(headers, width)
        divider = Array.new(width, "---")

        ([ headers, divider ] + rows.map { |r| pad(r, width) })
          .map { |cols| "| #{cols.join(' | ')} |" }
          .join("\n")
      end

      def heading_text(cell)
        cell.is_a?(Hash) ? escape(cell[:text].to_s) : escape(cell.to_s)
      end

      def cell_text(cell)
        raw = cell.is_a?(Hash) ? cell[:text].to_s : cell.to_s
        escape(inline_text(raw))
      end

      def pad(cols, width)
        cols + Array.new([ width - cols.size, 0 ].max, "")
      end

      # Cells are markdown table content: escape pipes and flatten newlines.
      def escape(str)
        str.to_s.gsub("|", "\\|").gsub(/\s*\n\s*/, " ").strip
      end

      # ── breakdown percentage lists (analyze `bars`) ────────────────────────────

      # `bars` is { metric => [ {key:, pct:}, … ] }; `bar_captions` is { metric => str }.
      def breakdown_lists(bars, captions)
        indifferent_hash(bars).map do |metric, slices|
          lines = [ "**#{humanize(metric)}**" ]
          caption = indifferent_hash(captions)[metric]
          lines << inline_text(caption.to_s) if caption.present?
          Array(slices).each do |slice|
            s = indifferent(slice)
            lines << "- #{s[:key]}: #{format_pct(s[:pct])}"
          end
          lines.join("\n")
        end.join("\n\n")
      end

      def format_pct(value)
        num = value.to_f
        num == num.round ? "#{num.round}%" : "#{num.round(1)}%"
      end

      # ── a channel's games grid (`games` array) ─────────────────────────────────

      def games_list(games)
        Array(games).map do |game|
          g = indifferent(game)
          "- ##{g[:id]} #{g[:title]} (#{g[:vids]} vids)"
        end.join("\n")
      end

      # ── computed analytics scalars (filled by the Executor) ────────────────────

      # `metrics` is { label => value } (or Array<[label, value]>) — the inline-
      # computed numbers the Executor substitutes for a pending analytics marker.
      def metrics_lines(metrics)
        pairs = metrics.is_a?(Hash) ? metrics.to_a : Array(metrics)
        pairs.map { |label, value| "- #{humanize(label)}: #{value}" }.join("\n")
      end

      # A copy-key-only payload (an error event) → the rendered string. A failed
      # render (retired key) falls back to the bare key rather than blanking out.
      def copy_text(payload)
        args = indifferent_hash(payload[:message_args]).symbolize_keys
        Pito::Copy.render(payload[:message_key].to_s, args)
      rescue StandardError
        payload[:message_key].to_s
      end

      # ── HTML → text ────────────────────────────────────────────────────────────

      # Block-aware: closing block tags + <br> become newlines, remaining tags are
      # stripped, and Nokogiri decodes entities. Whitespace is squeezed; blank lines
      # collapse. This is the projection for every HTML-only card (detail/shinies/
      # similar) — the content is readable prose, just not structured.
      BLOCK_CLOSE = %r{</(?:p|div|li|tr|ul|ol|table|thead|tbody|section|article|header|footer|h[1-6])>}i
      BR_TAG      = %r{<br\s*/?>}i

      def html_to_text(html)
        return "" if html.blank?

        marked = html.to_s.gsub(BLOCK_CLOSE, "\n").gsub(BR_TAG, "\n")
        Nokogiri::HTML.fragment(marked).text
          .gsub("\r", "")
          .gsub(/[ \t]+/, " ")
          .split("\n").map(&:strip).reject(&:empty?).join("\n")
      end

      # Inline HTML strip (no block-newlines) — for table cells and captions.
      def inline_text(html)
        return "" if html.blank?

        Nokogiri::HTML.fragment(html.to_s).text.gsub(/\s+/, " ").strip
      end

      # ── helpers ────────────────────────────────────────────────────────────────

      def event_payload(event)
        return {} unless event.respond_to?(:[])

        event[:payload] || event["payload"] || {}
      end

      def humanize(key)
        key.to_s.tr("_", " ")
      end

      # Wrap a payload/hash for symbol-or-string key access; pass through non-hashes.
      def indifferent(obj)
        obj.is_a?(Hash) ? obj.with_indifferent_access : obj
      end

      def indifferent_hash(obj)
        obj.is_a?(Hash) ? obj.with_indifferent_access : {}
      end
    end
  end
end
