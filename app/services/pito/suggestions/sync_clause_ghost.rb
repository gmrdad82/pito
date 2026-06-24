# frozen_string_literal: true

module Pito
  module Suggestions
    # Inline ghost text for `sync channels [with <items>]`. Mirrors
    # ListClauseGhost; called by Engine#free_completions before the generic
    # compute_ghost when the spec is :sync.
    #
    # ghost(text) → { complete_current:, next_hint: } or nil (fall through).
    module SyncClauseGhost
      module_function

      WITH_ITEMS = %w[vids].freeze

      def ghost(text)
        # WITH context — after "sync channels with <partial>"
        if (m = text.match(/\bchannels?\s+with\s+(.*)\z/i))
          partial = m[1].to_s.lstrip.downcase
          return build_ghost(WITH_ITEMS, partial)
        end

        # CONNECTOR context — after "sync channels " suggest the `with` connector.
        if (m = text.match(/\bchannels?\b\s+(.*)\z/i))
          tail    = m[1]
          partial = tail.end_with?(" ") || tail.empty? ? "" : tail.split(/\s+/).last.to_s.downcase
          return build_ghost([ "with" ], partial)
        end

        nil
      end

      # Builds the ghost hash from candidates + partial.
      # Copied verbatim from ListClauseGhost#build_ghost.
      def build_ghost(candidates, partial)
        complete_current = if partial.empty?
          candidates.first.to_s
        else
          matches = candidates.select { |c| c.to_s.start_with?(partial) }
          matches.size == 1 ? matches.first.to_s[partial.length..] : ""
        end

        { complete_current: complete_current, next_hint: "" }
      end
      private_class_method :build_ghost
    end
  end
end
