# frozen_string_literal: true

module Pito
  module Grammar
    # The single, config-declared view of what a tool can do (v1.6 unified grammar).
    # Reads the per-tool `capabilities:` block from tools.yml and exposes the column /
    # filter vocabulary as plain data. `--help`, the MCP tool schema, and the
    # autocomplete engine ALL consume THIS — never their own hardcoded lists — so the
    # chatbox and MCP stay one grammar. The rendering BEHAVIOR (cell/sort procs, filter
    # scopes) lives in Ruby keyed by these names; the orphan-guard spec keeps the two
    # in 1:1 sync, and the help/autocomplete guards require a copy key on each element.
    module Capability
      module_function

      Column = Data.define(:name, :aliases, :sortable, :requires_with, :internal, :default, :desc) do
        # Every token that resolves to this column (canonical + aliases).
        def tokens = [ name, *aliases ]
      end

      Filter = Data.define(:name, :tokens, :vocabulary, :scope, :desc)

      # Columns for a tool+noun (config order preserved). [] when none declared.
      def columns(tool, noun)
        raw_columns(tool, noun).map do |name, spec|
          Column.new(
            name:          name.to_s,
            aliases:       Array(spec[:aliases]).map(&:to_s),
            sortable:      spec.fetch(:sortable, false),
            requires_with: spec.fetch(:requires_with, true),
            internal:      spec.fetch(:internal, false),
            default:       spec.fetch(:default, false),
            desc:          spec[:desc]
          )
        end
      end

      # Public (non-internal) columns — what --help / MCP / autocomplete surface.
      def public_columns(tool, noun)
        columns(tool, noun).reject(&:internal)
      end

      # Filters for a tool+noun. [] when none.
      def filters(tool, noun)
        raw_filters(tool, noun).map do |name, spec|
          Filter.new(
            name:       name.to_s,
            tokens:     Array(spec[:tokens]).map(&:to_s),
            vocabulary: spec[:vocabulary]&.to_s,
            scope:      spec[:scope]&.to_s,
            desc:       spec[:desc]
          )
        end
      end

      # alias/name (downcased) → canonical column Symbol — the vocabulary WithColumns
      # parses against, derived from config so it can never drift from --help/MCP.
      def column_vocabulary(tool, noun)
        public_columns(tool, noun).each_with_object({}) do |col, vocab|
          col.tokens.each { |t| vocab[t.downcase] = col.name.to_sym }
        end
      end

      # Canonical sortable column names (+ their tokens) for a tool+noun.
      def sortable_columns(tool, noun)
        columns(tool, noun).select(&:sortable)
      end

      # Every PASSABLE token for a filter: its literal `tokens:` plus, for a
      # vocabulary-backed filter, the vocabulary's members (downcased) and
      # synonym keys. This is what --help and the MCP schema advertise as
      # values that genuinely filter — tokens of 3+ words are excluded because
      # the chat grammar matches at most two-word phrases.
      def filter_tokens(filter)
        vocab = filter.vocabulary && Pito::Grammar::Registry.vocabulary(filter.vocabulary.to_sym)
        return filter.tokens unless vocab

        (filter.tokens +
          vocab.canonical.map(&:downcase) +
          vocab.synonyms.keys.map(&:to_s)).uniq.reject { |t| t.split.size > 2 }
      end

      # ── internals ──────────────────────────────────────────────────────────────

      def raw_columns(tool, noun)
        cap_dig(tool, :columns, noun)
      end

      def raw_filters(tool, noun)
        cap_dig(tool, :filters, noun)
      end

      def cap_dig(tool, section, noun)
        Pito::Dispatch::Config.data
                              .dig(:tools, tool.to_sym, :capabilities, section, noun.to_sym) || {}
      end
    end
  end
end
