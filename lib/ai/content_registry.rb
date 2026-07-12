# frozen_string_literal: true

module Ai
  # The AI content ontology — loads, validates, and freezes
  # config/pito/content.yml: the single declaration of the blocks the model
  # may compose (pito_respond), their data shapes, limits, and the global
  # content rules (no emoji / kaomoji, inline styling, the allowed colors).
  #
  # Mirrors Ai::ProviderRegistry: strict schema (unknown keys raise with a
  # did-you-mean), frozen after load, `reload!` for specs. Consumers:
  #
  #   * Ai::Toolset          — generates the pito_respond tool document
  #   * Ai::Blocks           — reads limits, chart vizzes, allowed colors
  #   * AiOrchestratorJob    — appends the content rules to the system prompt
  #   * TextBlockComponent   — renders the declared inline styling
  #
  # Presentation NEVER lives here — the ontology describes meaning and data,
  # the app owns every pixel.
  module ContentRegistry
    module_function

    class InvalidContent < StandardError; end

    PATH = Rails.root.join("config/pito/content.yml")

    TOP_KEYS   = %w[schema_version rules inline blocks limits].freeze
    BLOCK_KEYS = %w[label about when_to_use data limits vizzes].freeze
    BLOCK_REQUIRED = %w[label about when_to_use data].freeze
    # The palette the renderer actually supports — a color declared in YAML
    # without support code must fail loudly at boot, not silently in a chat.
    SUPPORTED_COLORS = %w[default cyan red green].freeze

    def data
      @data ||= load_and_validate
    end

    def reload!
      @data = nil
    end

    def rules
      data["rules"]
    end

    def inline
      data["inline"]
    end

    def blocks
      data["blocks"]
    end

    def block_types
      blocks.keys
    end

    def allowed_colors
      Array(inline.dig("colors", "allowed"))
    end

    def chart_vizzes
      blocks.dig("chart", "vizzes")&.keys || []
    end

    # A limit by path with a Ruby fallback — limit("text", "max_chars",
    # default: 4000) or the answer-level limit("max_blocks", default: 12).
    def limit(*path, default:)
      value =
        if path.length == 1
          data.dig("limits", path.first)
        else
          blocks.dig(path.first, "limits", *path[1..])
        end
      value.nil? ? default : Integer(value)
    end

    # ── generated documents ────────────────────────────────────────────────

    # The pito_respond tool description, generated from the ontology — the
    # model's complete guide to composing an answer.
    def respond_description
      out = []
      out << "End your turn with your own composed answer as typed blocks. " \
             "Prefer structured blocks over prose paragraphs. " \
             "You write every label, caption, and note yourself."
      out << ""
      out << prompt_rules
      out << ""
      out << "Inline styling (paragraph text only): #{inline["bold"]}, #{inline["italic"]}, " \
             "colors #{inline.dig("colors", "notation")} — allowed colors: #{allowed_colors.join(", ")}."
      if inline["subject"] || inline["reference"]
        out << "Semantic tokens (paragraph text only — mark MEANING, pito styles them): " \
               "#{[ inline["subject"], inline["reference"] ].compact.join(" · ")}"
      end
      out << ""
      out << "Block types (each an object with \"type\" plus its keys):"
      blocks.each do |type, decl|
        out << ""
        out << "#{type} — #{decl["label"]}"
        out << "  #{decl["about"]}"
        out << "  Use when: #{decl["when_to_use"]}"
        out << "  Data: #{format_fields(decl["data"])}"
        decl["vizzes"]&.each do |viz, vdecl|
          out << "  viz=#{viz}: #{vdecl["about"]}"
          out << "    Data: #{format_fields(vdecl["data"])}"
        end
        if decl["limits"].present?
          out << "  Limits: #{decl["limits"].map { |k, v| "#{k}=#{v}" }.join(", ")}"
        end
      end
      out << ""
      out << "At most #{limit("max_blocks", default: 12)} blocks per answer."
      out.join("\n")
    end

    # The global content rules as prompt bullet lines.
    def prompt_rules
      rules.map { |name, text| "- #{name}: #{text}" }.join("\n")
    end

    # ── internals ──────────────────────────────────────────────────────────

    def format_fields(fields)
      Hash(fields).map { |name, doc| "#{name}: #{doc}" }.join("; ")
    end

    def load_and_validate
      doc = YAML.safe_load_file(PATH, aliases: false)
      validate!(doc)
      doc.freeze
    end

    def validate!(doc)
      raise InvalidContent, "content.yml must be a mapping" unless doc.is_a?(Hash)

      assert_keys!(doc.keys, TOP_KEYS, where: "top level")
      TOP_KEYS.each { |k| raise InvalidContent, "content.yml missing `#{k}`" unless doc.key?(k) }

      blocks = doc["blocks"]
      raise InvalidContent, "content.yml `blocks` must be a non-empty mapping" unless blocks.is_a?(Hash) && blocks.any?

      blocks.each do |type, decl|
        raise InvalidContent, "block `#{type}` must be a mapping" unless decl.is_a?(Hash)

        assert_keys!(decl.keys, BLOCK_KEYS, where: "block `#{type}`")
        BLOCK_REQUIRED.each do |k|
          raise InvalidContent, "block `#{type}` missing `#{k}`" if decl[k].blank?
        end
        if decl.key?("vizzes") && type != "chart"
          raise InvalidContent, "block `#{type}` declares `vizzes` — only `chart` carries vizzes"
        end
      end

      colors = Array(doc.dig("inline", "colors", "allowed"))
      unsupported = colors - SUPPORTED_COLORS
      if unsupported.any?
        raise InvalidContent,
              "content.yml allows unsupported color(s) #{unsupported.join(", ")} — " \
              "supported: #{SUPPORTED_COLORS.join(", ")} (add the support code first)"
      end
      raise InvalidContent, "content.yml must allow at least the default color" unless colors.include?("default")
    end

    def assert_keys!(keys, allowed, where:)
      unknown = keys.map(&:to_s) - allowed
      return if unknown.empty?

      hints = unknown.map do |key|
        best = allowed.min_by { |a| levenshtein(key, a) }
        "`#{key}`#{" (did you mean `#{best}`?)" if best && levenshtein(key, best) <= 3}"
      end
      raise InvalidContent, "content.yml unknown key(s) at #{where}: #{hints.join(", ")}"
    end

    def levenshtein(a, b)
      DidYouMean::Levenshtein.distance(a, b)
    end
  end
end
