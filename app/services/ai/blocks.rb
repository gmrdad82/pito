# frozen_string_literal: true

module Ai
  # Validates + normalizes the model's pito_respond blocks into the exact
  # shapes the block components consume. The model chooses CONTENT, never
  # markup: every value here is clamped, coerced, and re-keyed; a block that
  # fails its type's rules DEGRADES to a text block carrying its JSON (the
  # message never errors on a bad block, and nothing the model sent is lost).
  #
  # Entity references (media blocks) are resolved server-side by id — the model
  # can never inject a URL. Suggestion commands must parse as a real pito verb
  # (and never `ai` itself), or the suggestion degrades.
  module Blocks
    module_function

    MAX_BLOCKS      = 12
    MAX_TEXT        = 4_000
    MAX_ROWS        = 20
    MAX_COLS        = 6
    MAX_SERIES      = 90
    MAX_BARS        = 5
    MAX_SUGGESTIONS = 5

    ENTITIES = {
      "game"    => { klass: -> { ::Game },    variants: %w[cover],         default: "cover" },
      "vid"     => { klass: -> { ::Video },   variants: %w[thumb],         default: "thumb" },
      "channel" => { klass: -> { ::Channel }, variants: %w[avatar banner], default: "avatar" }
    }.freeze

    CHART_VIZ = %w[area bar heatmap].freeze

    # @param raw          [Array] the model's blocks (hashes, any key style)
    # @param conversation [Conversation] grammar context for suggestion parsing
    # @return [Array<Hash>] normalized, string-keyed blocks (≤ MAX_BLOCKS)
    def normalize(raw, conversation:)
      suggestions = 0

      Array(raw).first(MAX_BLOCKS).filter_map do |block|
        next unless block.is_a?(Hash)

        b = deep_stringify(block)
        case b["type"].to_s
        when "text"       then text(b)
        when "kv_table"   then kv_table(b)
        when "table"      then table(b)
        when "media"      then media(b)
        when "sparkline"  then sparkline(b)
        when "chart"      then chart(b)
        when "score"      then score(b)
        when "ttb"        then ttb(b)
        when "suggestion"
          next degrade(b) if (suggestions += 1) > MAX_SUGGESTIONS

          suggestion(b, conversation)
        else degrade(b)
        end
      end
    end

    def text_block(text)
      { "type" => "text", "text" => text.to_s.strip[0, MAX_TEXT] }
    end

    # ── per-type rules (nil never escapes: failures degrade) ──────────────────

    def text(b)
      value = b["text"].to_s.strip
      value.present? ? text_block(value) : nil
    end

    def kv_table(b)
      rows = Array(b["rows"]).first(MAX_ROWS).filter_map do |row|
        pair = Array(row).map(&:to_s)
        pair if pair.size == 2
      end
      rows.any? ? { "type" => "kv_table", "rows" => rows } : degrade(b)
    end

    def table(b)
      header = Array(b["header"]).first(MAX_COLS).map(&:to_s)
      return degrade(b) if header.empty?

      rows = Array(b["rows"]).first(MAX_ROWS).map do |row|
        cells = Array(row).first(header.size).map(&:to_s)
        cells + Array.new(header.size - cells.size, "")
      end
      return degrade(b) if rows.empty? # the grid renders nothing without rows

      { "type" => "table", "header" => header, "rows" => rows }
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
      out["label"]      = b["label"].to_s if b["label"].present?
      out["series_max"] = [ b["series_max"].to_f, 0.0 ].max if b["series_max"].present?
      out
    end

    # area renders through the same braille area engine as the sparkline (the
    # full ticked Area chart joins once its metric preset is generalized);
    # bar/heatmap map onto their kwargs-pure visualizers.
    def chart(b)
      viz  = b["viz"].to_s
      data = b["data"].is_a?(Hash) ? b["data"] : {}
      return degrade(b) unless CHART_VIZ.include?(viz)

      out =
        case viz
        when "area"
          series = numeric_series(data["series"])
          series.any? ? { "viz" => "area", "series" => series } : nil
        when "bar"
          bars = Array(data["bars"]).first(MAX_BARS).filter_map do |bar|
            next unless bar.is_a?(Hash)

            h = deep_stringify(bar)
            next if h["label"].to_s.blank?

            { "label" => h["label"].to_s, "pct" => h["pct"].to_f.clamp(0.0, 100.0) }
              .merge(h["value_label"].present? ? { "value_label" => h["value_label"].to_s } : {})
          end
          bars.any? ? { "viz" => "bar", "bars" => bars } : nil
        when "heatmap"
          values = numeric_series(data["values"])
          values.size == 7 ? { "viz" => "heatmap", "values" => values } : nil
        end
      return degrade(b) if out.nil?

      out["label"] = b["label"].to_s if b["label"].present?
      { "type" => "chart" }.merge(out)
    end

    def score(b)
      value = b["value"]
      return degrade(b) unless value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/)

      out = { "type" => "score", "value" => value.to_i.clamp(0, 100) }
      out["label"] = b["label"].to_s if b["label"].present?
      out
    end

    def ttb(b)
      hours = b["hours"].is_a?(Hash) ? deep_stringify(b["hours"]) : {}
      main  = hours["main"].to_f
      return degrade(b) if main <= 0

      out = { "type" => "ttb", "hours" => {
        "main"          => main,
        "extras"        => [ hours["extras"].to_f, 0.0 ].max,
        "completionist" => [ hours["completionist"].to_f, 0.0 ].max
      } }
      out["footage_hours"] = [ b["footage_hours"].to_f, 0.0 ].max if b["footage_hours"].present?
      out["label"]         = b["label"].to_s if b["label"].present?
      out
    end

    def suggestion(b, conversation)
      command = b["command"].to_s.strip
      return degrade(b) if command.blank?

      verb = Pito::Dispatch::UniversalReply.chat_verb(command, conversation)
      return degrade(b) if verb.blank? || verb == "unknown" || verb == "ai"

      out = { "type" => "suggestion", "command" => command }
      out["note"] = b["note"].to_s if b["note"].present?
      out
    end

    # A block that failed its rules still shows what the model meant.
    def degrade(b)
      text_block(JSON.generate(b))
    end

    def numeric_series(values)
      Array(values).first(MAX_SERIES).map { |v| [ v.to_f, 0.0 ].max }
    end

    def deep_stringify(hash)
      hash.respond_to?(:deep_stringify_keys) ? hash.deep_stringify_keys : hash
    end
  end
end
