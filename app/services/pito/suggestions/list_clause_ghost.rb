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
        # Candidates: the `with` connector (primary, shown for an empty partial),
        # `sorted by` (so "list games so" → "rted by"), and `--help`
        # (so "list games --h" → "elp").
        if (m = text.match(/\b(?:games?|videos?)\b\s+(.*)\z/i))
          tail    = m[1]
          partial = tail.end_with?(" ") || tail.empty? ? "" : tail.split(/\s+/).last.to_s.downcase
          return build_ghost([ "with", "sorted by", "--help" ], partial)
        end

        nil
      end

      # ── Hashtag add/remove column ghost ────────────────────────────────────

      # Computes a column-ghost for `#<handle> add <partial>` / `#<handle> remove <partial>`
      # when the resolved follow-up reply_target is "game_list" or "video_list".
      #
      # @param target       [String]  "game_list" or "video_list"
      # @param args_text    [String]  everything after the action verb (e.g. "platform, ")
      # @param ends_with_space [Boolean]  whether the full input ends with a space
      # @return [Hash{ menu_items: [], ghost: {complete_current:, next_hint:} }, nil]
      #         nil when target is not a list target
      def hashtag_list_action_completions(target, args_text, ends_with_space)
        registry = case target
        when "game_list"  then Pito::MessageBuilder::Game::ListColumns
        when "video_list" then Pito::MessageBuilder::Video::ListColumns
        else return nil
        end

        # Parse the comma-separated tokens from args_text.
        # e.g. "platform, " → segments ["platform", ""] (trailing empty = cursor past comma)
        # e.g. "platform, gen" → segments ["platform", "gen"]
        # e.g. "" → segments [""]
        segments = args_text.to_s.split(/\s*,\s*/, -1)
        partial   = ends_with_space ? "" : segments.last.to_s.lstrip.downcase

        # Tokens before the last segment are fully typed; resolve to canonicals.
        already_used = already_used_tokens(segments, registry)

        # Candidates = all suggestion tokens minus already-used display tokens.
        candidates = registry.suggestion_tokens - already_used

        ghost = build_ghost(candidates, partial)
        { menu_items: action_menu_items(candidates, partial), ghost: ghost }
      end

      # Menu palette of the column candidates that match the partial (all of them
      # when the partial is empty) — mirrors the verb-stage follow-up menu so
      # `#<handle> add `/`remove ` surface a picker, not just an inline ghost.
      def action_menu_items(candidates, partial)
        matching = partial.empty? ? candidates : candidates.select { |c| c.to_s.start_with?(partial) }
        matching.map { |c| { label: c.to_s, insert: "#{c} ", description: "", masked: false } }
      end
      private_class_method :action_menu_items

      # ── Hashtag sort/order ghost ────────────────────────────────────────────────

      # Computes a sort-column ghost for `#<handle> sort <partial>` / `order <partial>`
      # when the resolved follow-up reply_target is "game_list" or "video_list".
      #
      # Candidates = base_sort_tokens + display tokens of sortable with-columns present
      # in +list_columns+.
      #
      # Ghost sequence:
      #   - When args_text is blank (nothing after the verb):    ghost "by"
      #   - When args_text starts with "b" (typing "by"):        ghost "by" completion
      #   - When args_text starts with "by " (with space):       ghost the first sort column
      #   - Otherwise:                                           ghost the sort column partial
      #
      # @param target          [String]        "game_list" or "video_list"
      # @param list_columns    [Array<String>] canonical column keys (strings) stamped in the event
      # @param args_text       [String]        everything after the action verb (e.g. "by vie")
      # @param ends_with_space [Boolean]       whether the full input ends with a space
      # @return [Hash{ menu_items: [], ghost: {complete_current:, next_hint:} }, nil]
      #         nil when target is not a list target
      def hashtag_list_sort_completions(target, list_columns:, args_text:, ends_with_space:)
        registry = case target
        when "game_list"  then Pito::MessageBuilder::Game::ListColumns
        when "video_list" then Pito::MessageBuilder::Video::ListColumns
        else return nil
        end

        # Build sortable candidates: base tokens + display tokens of present with-columns
        # that have a SORT_SPECS entry.
        present_sortable = Array(list_columns).map(&:to_sym).filter_map do |canonical|
          next unless registry::SORT_SPECS.key?(canonical) &&
                      registry::SORT_SPECS[canonical][:requires_with]

          registry.display_token(canonical)
        end.compact

        candidates = registry.base_sort_tokens + present_sortable

        # Determine what has been typed after the verb.
        tail = args_text.to_s

        # Nothing typed yet → ghost "by"
        if tail.strip.empty?
          ghost = { complete_current: "by", next_hint: "" }
          return { menu_items: [], ghost: ghost }
        end

        # Check whether "by" has been typed (with trailing space) → ghost column.
        if (m = tail.match(/\Aby(\s+)(.*)\z/i))
          col_partial = ends_with_space ? "" : m[2].to_s.strip.downcase
          ghost = build_ghost(candidates, col_partial)
          return { menu_items: [], ghost: ghost }
        end

        # Still typing "by" itself (no trailing space after "by").
        if tail.downcase.start_with?("b") && !ends_with_space
          partial = tail.downcase
          ghost   = build_ghost([ "by" ], partial)
          return { menu_items: [], ghost: ghost }
        end

        # Anything else (e.g. user skipped "by" and typed the column directly).
        col_partial = ends_with_space ? "" : tail.strip.downcase
        ghost = build_ghost(candidates, col_partial)
        { menu_items: [], ghost: ghost }
      end

      # ── Private helpers ────────────────────────────────────────────────────

      # Returns the registry module for the noun in text, or nil for channels.
      # The noun is read from the head (before any `with` / `sorted by` clause) so a
      # column name inside the clause — e.g. the games `channels` column — is not
      # mistaken for the `list channels` noun (which would disable the ghost).
      def registry_for(text)
        head = text.split(/\b(?:with|sorted\s+by|ordered\s+by)\b/i, 2).first.to_s
        return nil if head.match?(/\bchannels?\b/i)

        if head.match?(/\bvideos?\b/i)
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
