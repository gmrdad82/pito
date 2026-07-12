# frozen_string_literal: true

module Ai
  # Validates + normalizes the model's pito_respond blocks into the exact
  # shapes the block components consume. The model chooses CONTENT, never
  # markup: every value here is clamped, coerced, and re-keyed; a block that
  # fails its type's rules DEGRADES to a text block carrying its JSON (the
  # message never errors on a bad block, and nothing the model sent is lost).
  #
  # Entity references (media blocks) are resolved server-side by id — the model
  # can never inject a URL. Suggestion commands must parse as a real pito tool
  # (and never `ai` itself), or the suggestion degrades.
  module Blocks
    module_function

    # Ruby fallbacks — the live caps come from config/pito/content.yml
    # (Ai::ContentRegistry.limit) so tuning a cap is a YAML edit.
    MAX_BLOCKS      = 12
    MAX_TEXT        = 4_000
    MAX_ROWS        = 20
    MAX_COLS        = 6
    MAX_SERIES      = 90
    MAX_BARS        = 5
    MAX_SUGGESTIONS = 5
    HEATMAP_MIN     = 2
    HEATMAP_MAX     = 42 # = the Heatmap visualizer's COLS canvas (1 braille cell per column)

    ENTITIES = {
      "game"    => { klass: -> { ::Game },    variants: %w[cover],         default: "cover" },
      "vid"     => { klass: -> { ::Video },   variants: %w[thumb],         default: "thumb" },
      "channel" => { klass: -> { ::Channel }, variants: %w[avatar banner], default: "avatar" }
    }.freeze

    def max_blocks      = Ai::ContentRegistry.limit("max_blocks", default: MAX_BLOCKS)
    def max_text        = Ai::ContentRegistry.limit("text", "max_chars", default: MAX_TEXT)
    def max_rows        = Ai::ContentRegistry.limit("kv_table", "max_rows", default: MAX_ROWS)
    def max_cols        = Ai::ContentRegistry.limit("table", "max_cols", default: MAX_COLS)
    def max_series      = Ai::ContentRegistry.limit("sparkline", "max_points", default: MAX_SERIES)
    def max_bars        = Ai::ContentRegistry.limit("chart", "max_bars", default: MAX_BARS)
    def max_suggestions = Ai::ContentRegistry.limit("suggestion", "max_per_answer", default: MAX_SUGGESTIONS)
    def heatmap_min     = Ai::ContentRegistry.limit("chart", "heatmap_min_values", default: HEATMAP_MIN)
    def heatmap_max     = Ai::ContentRegistry.limit("chart", "heatmap_max_values", default: HEATMAP_MAX)

    def chart_vizzes
      vizzes = Ai::ContentRegistry.chart_vizzes
      vizzes.any? ? vizzes : %w[area bar heatmap heart]
    end

    # @param raw          [Array] the model's blocks (hashes, any key style)
    # @param conversation [Conversation] grammar context for suggestion parsing
    # @return [Array<Hash>] normalized, string-keyed blocks (≤ MAX_BLOCKS)
    def normalize(raw, conversation:)
      suggestions = 0

      Array(raw).first(max_blocks).flat_map do |block|
        next [] unless block.is_a?(Hash)

        b = deep_stringify(block)
        out =
          case b["type"].to_s
          when "text"       then text(b) # may split into [text, table, …]
          when "kv_table"   then kv_table(b, conversation)
          when "table"      then table(b)
          when "media"      then media(b)
          when "sparkline"  then sparkline(b)
          when "chart"      then chart(b)
          when "score"      then score(b)
          when "ttb"        then ttb(b)
          when "suggestion"
            next [ degrade(b) ] if (suggestions += 1) > max_suggestions

            suggestion(b, conversation)
          else degrade(b)
          end
        out.is_a?(Array) ? out : [ out ].compact
      end.first(max_blocks)
    end

    def text_block(text)
      { "type" => "text", "text" => text.to_s.strip[0, max_text] }
    end

    # Free prose → blocks, WITH pipe-table extraction — the entry point for
    # text that never went through normalize (bare-text stops, prose sent
    # alongside a terminal tool). text_block stays raw: degrade() must never
    # re-parse the JSON it wraps.
    def text_blocks(text)
      value = text.to_s.strip
      return [] if value.blank?

      extract_pipe_tables(value)
    end

    # ── per-type rules (nil never escapes: failures degrade) ──────────────────

    # Models leak markdown pipe-tables into prose no matter what the prompt
    # says — extract them into real table blocks (component-rendered, kv-table
    # palette) instead of showing raw "| a | b |" lines. The surrounding prose
    # stays as text blocks, in order.
    def text(b)
      value = b["text"].to_s.strip
      return nil if value.blank?

      text_blocks(value)
    end

    PIPE_ROW       = /\A\s*\|.*\|\s*\z/
    PIPE_SEPARATOR = /\A\s*\|[\s\-:|]+\|\s*\z/

    def extract_pipe_tables(value)
      blocks = []
      buffer = []
      lines  = value.split("\n")

      i = 0
      while i < lines.size
        # A table starts at a pipe row whose NEXT line is the |---| separator.
        unless lines[i].match?(PIPE_ROW) && lines[i + 1]&.match?(PIPE_SEPARATOR)
          buffer << lines[i]
          i += 1
          next
        end

        run = []
        while i < lines.size && lines[i].match?(PIPE_ROW)
          run << lines[i]
          i += 1
        end

        table = pipe_table_block(run)
        if table
          flush_text(blocks, buffer)
          blocks << table
        else
          buffer.concat(run) # not parseable after all — keep the raw lines
        end
      end

      flush_text(blocks, buffer)
      blocks
    end

    def pipe_table_block(run)
      header = pipe_cells(run[0])
      rows   = run.drop(2).map { |line| pipe_cells(line) }
      return nil if header.empty? || rows.empty?

      table({ "type" => "table", "header" => header, "rows" => rows })
    end

    def pipe_cells(line)
      line.to_s.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip)
    end

    def flush_text(blocks, buffer)
      joined = buffer.join("\n").strip
      blocks << text_block(joined) if joined.present?
      buffer.clear
    end

    KV_VALUE_FORMATS = %w[price date number score].freeze

    # Rows arrive as [key, value] pairs OR {key:, value:, command:} objects.
    # A value may itself be typed — {v:, format: price|date|number|score} —
    # which the component right-aligns and renders through the house
    # formatters (price = the show-game coin display). `command` (validated
    # like a suggestion) makes the row's key click-to-prefill.
    def kv_table(b, conversation = nil)
      rows = Array(b["rows"]).first(max_rows).filter_map do |row|
        kv_row(row, conversation)
      end
      rows.any? ? { "type" => "kv_table", "rows" => rows } : degrade(b)
    end

    def kv_row(row, conversation = nil)
      if row.is_a?(Hash)
        r = deep_stringify(row)
        return nil if r["key"].blank?

        out = [ plain(r["key"]), kv_value(r["value"]) ]
        cmd = runnable_command(r["command"], conversation:)
        out << cmd if cmd
        out
      else
        pair = Array(row)
        return nil unless pair.size == 2

        [ plain(pair[0]), kv_value(pair[1]) ]
      end
    end

    def kv_value(value)
      if value.is_a?(Hash)
        v = deep_stringify(value)
        format = v["format"].to_s
        return plain(v.to_s) unless KV_VALUE_FORMATS.include?(format) && !v["v"].nil?

        { "v" => v["v"].to_s, "format" => format }
      else
        plain(value)
      end
    end

    def table(b)
      header = Array(b["header"]).first(max_cols).map { |c| plain(c) }
      return degrade(b) if header.empty?

      rows = Array(b["rows"]).first(max_rows).map do |row|
        cells = Array(row).first(header.size).map { |c| plain(c) }
        cells + Array.new(header.size - cells.size, "")
      end
      return degrade(b) if rows.empty? # the grid renders nothing without rows

      { "type" => "table", "header" => header, "rows" => rows }
    end

    # Styling notation belongs to paragraphs alone — in cells, keys, and
    # labels the markers are noise ("**94**" in a table cell): unwrap them.
    def plain(value)
      value.to_s
           .gsub(/\*\*(.+?)\*\*/m, '\1')
           .gsub(/\*([^*\n]+)\*/, '\1')
    end

    # A row-level command, validated exactly like a suggestion's — nil when
    # it isn't a runnable pito command.
    def runnable_command(command, conversation: nil)
      cmd = command.to_s.strip
      return nil if cmd.blank?

      tool = Pito::Dispatch::UniversalReply.chat_tool(cmd, conversation)
      return nil if tool.blank? || tool == "unknown" || tool == "@ai"

      cmd
    end

    def media(b)
      entity = ENTITIES[b["entity"].to_s]
      id     = b["id"].to_i
      return degrade(b) if entity.nil? || id <= 0
      return degrade(b) unless entity[:klass].call.exists?(id:)

      variant = entity[:variants].include?(b["variant"].to_s) ? b["variant"].to_s : entity[:default]
      { "type" => "media", "entity" => b["entity"].to_s, "id" => id, "variant" => variant }
    end

    def sparkline(b)
      series = numeric_series(b["series"])
      return degrade(b) if series.empty?

      out = { "type" => "sparkline", "series" => series }
      out["label"]      = plain(b["label"]) if b["label"].present?
      out["series_max"] = [ b["series_max"].to_f, 0.0 ].max if b["series_max"].present?
      out
    end

    # area renders through the same braille area engine as the sparkline (the
    # full ticked Area chart joins once its metric preset is generalized);
    # bar/heatmap map onto their kwargs-pure visualizers (heatmap: 2..42
    # values, optional 1:1 labels, weekday preset at a bare 7).
    def chart(b)
      viz  = b["viz"].to_s
      data = b["data"].is_a?(Hash) ? b["data"] : {}
      return degrade(b) unless chart_vizzes.include?(viz)

      out =
        case viz
        when "area"
          series = numeric_series(data["series"])
          if series.any?
            area = { "viz" => "area", "series" => series }
            area["target"] = [ data["target"].to_f, 0.0 ].max if data["target"].present?
            area["format"] = data["format"].to_s if %w[count duration percent].include?(data["format"].to_s)
            if data["dates"].is_a?(Array) && data["dates"].size == series.size
              area["dates"] = data["dates"].map(&:to_s)
            end
            area
          end
        when "bar"
          bars = Array(data["bars"]).first(max_bars).filter_map do |bar|
            next unless bar.is_a?(Hash)

            h = deep_stringify(bar)
            next if h["label"].to_s.blank?
            # A zero bar draws nothing and reads as noise (owner law) — drop it;
            # content.yml also tells the model not to send them.
            next if h["pct"].to_f <= 0.0

            { "label" => h["label"].to_s, "pct" => h["pct"].to_f.clamp(0.0, 100.0) }
              .merge(h["value_label"].present? ? { "value_label" => h["value_label"].to_s } : {})
          end
          bars.any? ? { "viz" => "bar", "bars" => bars } : nil
        when "heatmap"
          heatmap(data)
        when "heart"
          if data["score"].present?
            {
              "viz"      => "heart",
              "score"    => data["score"].to_i.clamp(0, 100),
              "likes"    => [ data["likes"].to_i, 0 ].max,
              "dislikes" => [ data["dislikes"].to_i, 0 ].max
            }
          end
        end
      return degrade(b) if out.nil?

      out["label"] = plain(b["label"]) if b["label"].present?
      { "type" => "chart" }.merge(out)
    end

    # 2..42 values over any interval; 7 without labels is the weekday preset.
    # `labels` (when given) must pair 1:1 with values — plain()-ed strings —
    # or the block refuses (nil → the caller degrades).
    def heatmap(data)
      values = numeric_series(data["values"])
      return nil unless values.size.between?(heatmap_min, heatmap_max)

      out = { "viz" => "heatmap", "values" => values }
      labels = data["labels"]
      return out if labels.nil?
      return nil unless labels.is_a?(Array) && labels.size == values.size

      out.merge("labels" => labels.map { |l| plain(l) })
    end

    def score(b)
      value = b["value"]
      return degrade(b) unless value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/)

      out = { "type" => "score", "value" => value.to_i.clamp(0, 100) }
      out["label"] = plain(b["label"]) if b["label"].present?
      out
    end

    # Generic effort gauge: ordered `levels` [{label, hours}, …] (1..3) plus an
    # optional `current` {label, hours} progress tracker. The legacy game shape
    # (`hours: {main, extras, completionist}` + `footage_hours`) maps onto the
    # same structure for compatibility.
    def ttb(b)
      levels = ttb_levels(b)
      return degrade(b) if levels.empty?

      out = { "type" => "ttb", "levels" => levels }
      current = ttb_current(b)
      out["current"] = current if current
      out["label"]   = plain(b["label"]) if b["label"].present?
      out
    end

    def ttb_levels(b)
      if b["levels"].present?
        Array(b["levels"]).first(3).filter_map do |level|
          next unless level.is_a?(Hash)

          l = deep_stringify(level)
          next if l["label"].to_s.blank? || l["hours"].to_f <= 0

          { "label" => l["label"].to_s, "hours" => l["hours"].to_f }
        end
      elsif b["hours"].is_a?(Hash)
        h = deep_stringify(b["hours"])
        %w[main extras completionist].filter_map do |name|
          { "label" => name, "hours" => h[name].to_f } if h[name].to_f.positive?
        end
      else
        []
      end
    end

    def ttb_current(b)
      if b["current"].is_a?(Hash)
        c = deep_stringify(b["current"])
        { "label" => c["label"].to_s.presence || "current", "hours" => [ c["hours"].to_f, 0.0 ].max }
      elsif b["footage_hours"].present?
        { "label" => "footage", "hours" => [ b["footage_hours"].to_f, 0.0 ].max }
      end
    end

    def suggestion(b, conversation)
      command = b["command"].to_s.strip
      return degrade(b) if command.blank?

      tool = Pito::Dispatch::UniversalReply.chat_tool(command, conversation)
      return degrade(b) if tool.blank? || tool == "unknown" || tool == "@ai"

      out = { "type" => "suggestion", "command" => command }
      out["note"] = plain(b["note"]) if b["note"].present?
      out
    end

    # A block that failed its rules still shows what the model meant.
    def degrade(b)
      text_block(JSON.generate(b))
    end

    def numeric_series(values)
      Array(values).first(max_series).map { |v| [ v.to_f, 0.0 ].max }
    end

    def deep_stringify(hash)
      hash.respond_to?(:deep_stringify_keys) ? hash.deep_stringify_keys : hash
    end
  end
end
