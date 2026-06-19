# frozen_string_literal: true

module Pito
  module Copy
    # Audits the copy dictionary.
    #
    # == Result shape
    #
    #   result = Pito::Copy::Audit.call
    #
    #   result.registered
    #   # => Array of { key: String, variants: Integer, placeholders: [String], single: Boolean }
    #   #    One entry per leaf under pito.copy.*.
    #
    #   result.legacy_candidates
    #   # => Array of { key: String, variants: Integer, placeholders: [String] }
    #   #    One entry per array-valued leaf OUTSIDE pito.copy.*.
    #
    # == Usage
    #
    #   Pito::Copy::Audit.call
    #
    module Audit
      # Returned by .call — carries both result lists.
      Result = Data.define(:registered, :legacy_candidates)

      COPY_NAMESPACE      = "pito.copy"
      PITO_NAMESPACE      = "pito"
      PLACEHOLDER_RE      = /%\{(\w+)\}/
      STANDARD_MIN_SIZE   = 50

      module_function

      # Runs the audit and returns a +Result+.
      #
      # @return [Pito::Copy::Audit::Result]
      def call
        ensure_translations_loaded!

        registered        = audit_registered
        legacy_candidates = audit_legacy_candidates

        Result.new(registered: registered, legacy_candidates: legacy_candidates)
      end

      # ── private helpers ────────────────────────────────────────────────────

      # Ensures I18n backend has loaded all translations before we walk the tree.
      def ensure_translations_loaded!
        backend = I18n.backend
        backend.send(:init_translations) unless backend.initialized?
      end
      private_class_method :ensure_translations_loaded!

      # Walks pito.copy.* and returns structured info for every leaf.
      def audit_registered
        copy_root = I18n.t(COPY_NAMESPACE, default: {})
        return [] unless copy_root.is_a?(Hash)

        leaves = []
        walk_leaves(copy_root, COPY_NAMESPACE) do |key, values|
          entries = Array(values)
          leaves << {
            key:             key,
            variants:        entries.size,
            placeholders:    extract_placeholders(entries),
            single:          entries.size == 1,
            below_standard:  entries.size < STANDARD_MIN_SIZE
          }
        end
        leaves.sort_by { |r| r[:key] }
      end
      private_class_method :audit_registered

      # Walks the pito.* locale tree (excluding pito.copy.*) and returns every
      # array-valued leaf as a migration candidate.  Scoping to pito.* keeps
      # the list focused on app copy and excludes Rails builtins, Faker data,
      # and other third-party i18n entries.
      def audit_legacy_candidates
        all_translations = I18n.backend.send(:translations)
        locale_tree      = all_translations[I18n.default_locale] || {}

        # Descend into the pito.* subtree only.
        pito_tree = locale_tree.dig(:pito) || {}

        candidates = []
        walk_leaves(pito_tree, PITO_NAMESPACE) do |key, value|
          next unless value.is_a?(Array)
          next if key == COPY_NAMESPACE || key.start_with?("#{COPY_NAMESPACE}.")

          candidates << {
            key:          key,
            variants:     value.size,
            placeholders: extract_placeholders(value)
          }
        end
        candidates.sort_by { |c| c[:key] }
      end
      private_class_method :audit_legacy_candidates

      # Recursively walks a translation subtree, yielding (dotted_key, value)
      # for every leaf (non-Hash) node.
      def walk_leaves(tree, prefix, &block)
        tree.each do |k, v|
          full_key = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
          if v.is_a?(Hash)
            walk_leaves(v, full_key, &block)
          else
            yield full_key, v
          end
        end
      end
      private_class_method :walk_leaves

      # Scans an array of strings for %{name} tokens and returns unique names.
      def extract_placeholders(entries)
        entries.flat_map { |e| e.to_s.scan(PLACEHOLDER_RE).flatten }.uniq.sort
      end
      private_class_method :extract_placeholders
    end
  end
end
