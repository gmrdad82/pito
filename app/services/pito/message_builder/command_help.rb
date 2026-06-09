# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Per-verb `--help` dispatcher.
    #
    # CommandHelp.call(verb: :show) → { "html" => true, "body" => <man page> }
    #                              or nil when no help copy exists for the verb.
    #
    # :list → delegates to Game::ListHelp (retains its own rendering path).
    # Other verbs → reads pito.copy.chat_help.<verb> from I18n:
    #   {
    #     "usage"    => "verb <args>",
    #     "sections" => { "Title" => { "token" => "description", … }, … }
    #   }
    # Returns nil when the key is missing or malformed.
    module CommandHelp
      module_function

      # @param verb [Symbol]
      # @return [Hash, nil]
      def call(verb:)
        return Pito::MessageBuilder::Game::ListHelp.call if verb == :list

        data = help_data(verb)
        return nil unless data.is_a?(Hash)

        # I18n returns symbol-keyed hashes for YAML mappings.
        usage    = (data[:usage] || data["usage"]).to_s
        sections = data[:sections] || data["sections"]
        return nil unless sections.is_a?(Hash)

        groups = sections.map do |title, rows|
          next nil unless rows.is_a?(Hash)

          [ title.to_s, rows.map { |tok, desc| [ tok.to_s, desc.to_s ] } ]
        end.compact

        return nil if groups.empty?

        body = Pito::MessageBuilder::ManPage.render(usage:, groups:)
        { "html" => true, "body" => body }
      end

      # ── Private ──────────────────────────────────────────────────────────────

      def help_data(verb)
        I18n.t("pito.copy.chat_help.#{verb}", default: nil)
      end
      private_class_method :help_data
    end
  end
end
