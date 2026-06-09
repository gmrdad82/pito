# frozen_string_literal: true

module Pito
  module Suggestions
    # Computes inline ghost text for the `with` and `sorted by` clauses of a
    # `list games` / `list videos` command.
    #
    # Called by Engine#free_completions BEFORE the generic compute_ghost when
    # the spec name is :list, so clause-aware completions take precedence.
    #
    # ghost(text) → { complete_current: String, next_hint: "" }
    #              or nil (fall through to generic ghost)
    module ListClauseGhost
      module_function

      # @param text [String] input left of the caret
      # @return [Hash{ complete_current: String, next_hint: String }, nil]
      def ghost(text)
        registry = registry_for(text)
        return nil if registry.nil?

        # SORT context — check before WITH so "with platform sorted by ti" works.
        if (m = text.match(/(?:sorted|ordered)\s+by\s+([^,]*)\z/i))
          partial    = m[1].lstrip.downcase
          candidates = registry.base_sort_tokens + present_with_tokens(text, registry)
          return build_ghost(candidates, partial)
        end

        # WITH context
        if (m = text.match(/\bwith\s+(.*)\z/i))
          with_text = m[1]
          segments  = with_text.split(/\s*,\s*/, -1)
          partial   = segments.last.to_s.lstrip.downcase

          # Parse already-used columns from all segments except the last.
          already_used = already_used_tokens(segments, registry)

          # Candidates = all suggestion tokens minus already-used display tokens.
          candidates = registry.suggestion_tokens - already_used
          return build_ghost(candidates, partial)
        end

        # CONNECTOR context — suggest the `with` connector after the noun.
        #
        # Matches when the user has typed the noun and at least one space
        # (e.g. "list games ").  The tail is everything after the noun; the
        # partial is the last whitespace-delimited token in that tail (or ""
        # when the tail is empty / ends with whitespace).
        #
        # The `with` and `sorted by` branches above take priority because they
        # are checked first — typing "list games with " still ghosts "platform".
        if (m = text.match(/\b(?:games?|videos?)\b\s+(.*)\z/i))
          tail    = m[1]
          partial = tail.end_with?(" ") || tail.empty? ? "" : tail.split(/\s+/).last.to_s.downcase
          return build_ghost(%w[with], partial)
        end

        nil
      end

      # ── Private helpers ────────────────────────────────────────────────────

      # Returns the registry module for the noun in text, or nil for channels.
      def registry_for(text)
        return nil if text.match?(/\bchannels?\b/i)

        if text.match?(/\bvideos?\b/i)
          Pito::MessageBuilder::Video::ListColumns
        else
          Pito::MessageBuilder::Game::ListColumns
        end
      end
      private_class_method :registry_for

      # Returns display tokens of the with-columns already typed (stops at sort clause).
      def present_with_tokens(text, registry)
        Pito::Chat::WithColumns.parse(text, vocabulary: registry.vocabulary)
          .map { |canonical| registry.display_token(canonical) }
          .compact
      end
      private_class_method :present_with_tokens

      # Returns display tokens of fully-typed columns from the segments before the
      # last (still-being-typed) segment.
      def already_used_tokens(segments, registry)
        done_segments = segments[0...-1]
        return [] if done_segments.empty?

        done_segments.filter_map do |seg|
          canonical = registry.vocabulary[seg.strip.downcase]
          canonical ? registry.display_token(canonical) : nil
        end
      end
      private_class_method :already_used_tokens

      # Builds the ghost hash from candidates + partial.
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
