# frozen_string_literal: true

module Pito
  module Suggestions
    # Computes autocomplete suggestions for a given input and cursor position.
    #
    # call(input:, cursor:, conversation: nil, authenticated: false) →
    #   {
    #     mode:       Symbol (:slash | :hashtag | :free | :none),
    #     menu_items: [ { label:, insert:, description:, masked: } ],
    #     ghost:      { complete_current:, next_hint: }
    #   }
    #
    # Tasks w + x:
    #   w — slash/hashtag/free mode detection + static slot resolution
    #   x — dynamic vocab resolution with auth-gating
    module Engine
      # Maximum number of dynamic suggestions returned per query.
      DYNAMIC_LIMIT = 20

      # Auth-gated dynamic vocabulary names — never resolved for unauthenticated users.
      AUTH_GATED_VOCABS = %i[channels conversations].freeze

      EMPTY_GHOST = { complete_current: "", next_hint: "" }.freeze

      class << self
        # @param input         [String]  full input text
        # @param cursor        [Integer] caret offset (chars from start)
        # @param conversation  [Object, nil]
        # @param authenticated [Boolean]
        # @return [Hash]
        def call(input:, cursor:, conversation: nil, authenticated: false)
          # Work only with text to the left of the caret.
          text = input.to_s[0...cursor.to_i] || ""

          mode = detect_mode(text)

          result = case mode
          when :slash    then slash_completions(text, authenticated:)
          when :hashtag  then hashtag_completions(text, conversation:)
          when :free     then free_completions(text, authenticated:)
          else           { menu_items: [], ghost: EMPTY_GHOST }
          end

          { mode: mode }.merge(result)
        end

        private

        # ── Mode detection ────────────────────────────────────────────────────

        # :slash    → text starts with "/"
        # :hashtag  → text starts with "#"
        # :free     → non-empty, doesn't start with "/" or "#"
        # :none     → empty or whitespace-only
        def detect_mode(text)
          stripped = text.lstrip
          return :none    if stripped.empty?
          return :slash   if stripped.start_with?("/")
          return :hashtag if stripped.start_with?("#")

          :free
        end

        # ── SLASH mode ────────────────────────────────────────────────────────

        def slash_completions(text, authenticated:)
          # Strip the leading "/" for analysis.
          after_slash = text.lstrip.delete_prefix("/")

          # VERB STAGE: no space has been typed yet after the slash (cursor is
          # within or immediately after the verb token, no trailing space).
          unless after_slash.include?(" ")
            return verb_stage_completions(after_slash, authenticated:)
          end

          # ARG STAGE: verb has been typed + at least one space.
          parts = after_slash.split(" ", -1)
          verb  = parts.first.to_s.downcase

          spec = Pito::Grammar::Registry.specs_for_alias(namespace: :slash, token: verb.to_sym)
          return { menu_items: [], ghost: EMPTY_GHOST } unless spec

          # The partial is everything after the last space.
          # If text ends with " ", partial is "".
          partial = after_slash.end_with?(" ") ? "" : parts.last.to_s

          # Already-consumed arg tokens (everything between verb and partial).
          # We need to figure out which slot is active.
          consumed_args = build_consumed_args(after_slash, partial)

          items = arg_stage_completions(spec, consumed_args, partial, authenticated:)
          ghost = kv_ghost_for(spec, consumed_args, partial)
          { menu_items: items, ghost: ghost }
        end

        # Returns all args that have been fully typed (before the current partial).
        # Handles "@handle" reconstruction for the channels vocab.
        def build_consumed_args(after_slash, partial)
          # Tokenise the portion before the partial.
          if partial.empty?
            prefix = after_slash
          else
            # Remove the trailing partial from the string.
            prefix = after_slash[0...after_slash.length - partial.length]
          end

          # Split on whitespace, drop the verb (first token).
          tokens = prefix.split.drop(1)
          tokens
        end

        # ── Verb stage ────────────────────────────────────────────────────────

        def verb_stage_completions(partial, authenticated:)
          all_slash_specs = Pito::Grammar::Registry.specs(namespace: :slash)

          filtered = all_slash_specs.select { |spec| include_slash_spec?(spec, authenticated:) }

          items = filtered
            .select { |spec| spec.name.to_s.start_with?(partial.downcase) }
            .map    { |spec| slash_verb_item(spec) }

          { menu_items: items, ghost: EMPTY_GHOST }
        end

        def include_slash_spec?(spec, authenticated:)
          if authenticated
            spec.auth != :unauthenticated_only
          else
            spec.auth == :unauthenticated_only
          end
        end

        def slash_verb_item(spec)
          {
            label:       "/#{spec.name}",
            insert:      "/#{spec.name} ",
            description: description_for(spec),
            masked:      false
          }
        end

        # ── Arg stage ────────────────────────────────────────────────────────

        # Walk the spec's slots, track which slots have been consumed, and
        # return suggestions for the active (current) slot.
        def arg_stage_completions(spec, consumed_args, partial, authenticated:)
          active_slot, resolved_values = find_active_slot_with_context(spec, consumed_args)
          return [] unless active_slot

          suggest_for_slot(active_slot, partial, authenticated:, resolved_values:)
        end

        # Determine which slot the cursor is currently in.
        # Walk consumed_args through the slot list using a greedy match.
        # The first slot that isn't filled is the active slot.
        # Tracks resolved_values so that conditional slots (slot.eligible?) are
        # honoured — e.g. after "/config sound " only the :state enum is active,
        # after "/config google " only the :settings kv is active.
        #
        # Returns the active slot (or nil). Use find_active_slot_with_context to
        # also receive the resolved_values Hash.
        def find_active_slot(spec, consumed_args)
          find_active_slot_with_context(spec, consumed_args).first
        end

        # Like find_active_slot but returns [active_slot, resolved_values].
        def find_active_slot_with_context(spec, consumed_args)
          slots = spec.slots.reject { |s| s.kind == :free || s.kind == :connective }
          return [ eligible_slots(slots, {}).first, {} ] if consumed_args.empty?

          remaining_args  = consumed_args.dup
          filled_slots    = []
          resolved_values = {}

          slots.each do |slot|
            break if remaining_args.empty?
            next unless slot.eligible?(resolved_values)

            case slot.kind
            when :literal, :enum
              # Consume one arg for a single-value slot (or one for each occurrence
              # of a repeatable slot as long as the arg could belong to this slot).
              if slot.repeatable?
                while remaining_args.any? && slot_matches_arg?(slot, remaining_args.first)
                  resolved_values[slot.name] = remaining_args.first
                  remaining_args.shift
                  filled_slots << slot
                end
              else
                if slot_matches_arg?(slot, remaining_args.first)
                  resolved_values[slot.name] = remaining_args.first
                  remaining_args.shift
                  filled_slots << slot
                end
              end
            when :kv
              # KV args look like "key=value" or "key:value" — consume while present.
              while remaining_args.any? && kv_arg?(remaining_args.first)
                remaining_args.shift
                filled_slots << slot
              end
            end
          end

          # The active slot is the first unfilled slot that is eligible given
          # the resolved values accumulated so far.
          # We do NOT fall back to .last — when all non-repeatable slots are
          # consumed the result is nil, which stops further suggestions.
          # Repeatable slots re-appear because s.repeatable? is true even after
          # they have been seen in filled_slots.
          consumed_slot_names = filled_slots.map(&:name)
          active = eligible_slots(slots, resolved_values).find do |s|
            !consumed_slot_names.include?(s.name) || s.repeatable?
          end

          [ active, resolved_values ]
        end

        # Returns slots that pass eligibility for the given resolved_values.
        def eligible_slots(slots, resolved_values)
          slots.select { |s| s.eligible?(resolved_values) }
        end

        # Check if a consumed arg string belongs to the given slot.
        def slot_matches_arg?(slot, arg_str)
          return false if arg_str.nil?
          vocab_name = slot.source
          return false unless vocab_name.is_a?(Symbol)
          vocab = Pito::Grammar::Registry.vocabulary(vocab_name)
          return false unless vocab

          if vocab.dynamic?
            # For dynamic vocabs, any non-empty arg is assumed to be a value attempt.
            true
          else
            vocab.resolve(arg_str.to_s) ? true : !vocab.canonical.empty?
          end
        end

        def kv_arg?(arg_str)
          arg_str.to_s.match?(/[=:]/)
        end

        # ── Slot suggestions ─────────────────────────────────────────────────

        def suggest_for_slot(slot, partial, authenticated:, resolved_values: {})
          case slot.kind
          when :literal, :enum
            suggest_vocab_slot(slot, partial, authenticated:)
          when :kv
            suggest_kv_slot(slot, partial, resolved_values:)
          else
            []
          end
        end

        def suggest_vocab_slot(slot, partial, authenticated:)
          vocab_name = slot.source
          return [] unless vocab_name.is_a?(Symbol)
          vocab = Pito::Grammar::Registry.vocabulary(vocab_name)
          return [] unless vocab

          if vocab.dynamic?
            suggest_dynamic(vocab, vocab_name, partial, authenticated:)
          else
            # Static vocab — filter canonical members by prefix.
            prefix_filter(vocab.canonical, partial).map do |member|
              { label: member, insert: "#{member} ", description: "", masked: false }
            end
          end
        end

        def suggest_kv_slot(slot, partial, resolved_values: {})
          vocab_name = slot.source
          return [] unless vocab_name.is_a?(Symbol)
          vocab = Pito::Grammar::Registry.vocabulary(vocab_name)
          return [] unless vocab

          masked_keys = Pito::Grammar::Vocabularies::MASKED_CONFIG_KEYS

          # When the user is still typing the key (no "=" in the partial yet),
          # filter the candidate keys by the per-provider allowed set so the
          # menu and ghost text are scoped to the active provider.
          if partial.present? && !partial.include?("=")
            provider = resolved_values[:provider].to_s.downcase
            candidate_keys = Pito::Grammar::Vocabularies.provider_keys(provider)
            # Fall back to the full vocab if the provider has no specific mapping.
            candidate_keys = vocab.canonical if candidate_keys.empty?

            matches = candidate_keys.select { |k| k.to_s.downcase.start_with?(partial.downcase) }
            return matches.map do |key|
              {
                label:       key,
                insert:      "#{key}=",
                description: "",
                masked:      masked_keys.include?(key)
              }
            end
          end

          # No partial key typed yet (or partial already has "=") — show all
          # keys for this provider, or the full vocab when no provider known.
          provider = resolved_values[:provider].to_s.downcase
          scoped_keys = Pito::Grammar::Vocabularies.provider_keys(provider)
          keys = scoped_keys.empty? ? vocab.canonical : scoped_keys

          keys.map do |key|
            {
              label:       key,
              insert:      "#{key}=",
              description: "",
              masked:      masked_keys.include?(key)
            }
          end
        end

        # Task x — dynamic slot resolution with auth-gating.
        def suggest_dynamic(vocab, vocab_name, partial, authenticated:)
          # AUTH GATING: block :channels and :conversations for unauthenticated users.
          if AUTH_GATED_VOCABS.include?(vocab_name) && !authenticated
            return []
          end

          begin
            # For :game_titles the resolver uses partial as an ILIKE query prefix.
            # For :channels/:conversations the resolver returns a full list; we prefix-filter.
            members = vocab.members(context: partial)
            members = members.first(DYNAMIC_LIMIT) if members.size > DYNAMIC_LIMIT

            # Prefix-filter (for vocabs that return broad lists).
            if vocab_name == :game_titles
              # The resolver already applies ILIKE "#{partial}%" so no further filtering needed,
              # but apply case-insensitive prefix check defensively.
              matches = members.select { |m| m.to_s.downcase.start_with?(partial.downcase) }
            else
              matches = prefix_filter(members.compact, partial)
            end

            matches.map do |member|
              { label: member.to_s, insert: "#{member} ", description: "", masked: false }
            end
          rescue StandardError
            []
          end
        end

        # ── KV ghost (P57) ───────────────────────────────────────────────────

        # When the active slot is a :kv slot and the user is still typing the
        # key portion (no "=" present), compute a ghost for the remaining chars
        # if exactly one provider key matches the partial prefix.
        # Returns EMPTY_GHOST when conditions aren't met or prefix is ambiguous.
        def kv_ghost_for(spec, consumed_args, partial)
          return EMPTY_GHOST if partial.empty? || partial.include?("=")

          active_slot, resolved_values = find_active_slot_with_context(spec, consumed_args)
          return EMPTY_GHOST unless active_slot&.kind == :kv

          provider = resolved_values[:provider].to_s.downcase
          candidate_keys = Pito::Grammar::Vocabularies.provider_keys(provider)

          if candidate_keys.empty?
            vocab = Pito::Grammar::Registry.vocabulary(active_slot.source)
            candidate_keys = vocab&.canonical || []
          end

          matches = candidate_keys.select { |k| k.to_s.downcase.start_with?(partial.downcase) }
          return EMPTY_GHOST unless matches.size == 1

          remainder = matches.first.to_s[partial.length..]
          { complete_current: remainder, next_hint: "" }
        end

        # ── HASHTAG mode ─────────────────────────────────────────────────────

        def hashtag_completions(text, conversation: nil)
          # Input looks like "#handle verb metric". The handle can contain a
          # hyphen (e.g. follow-up handles `alpha-1266`), which the lexer would
          # split — so extract the full `#<handle>` directly from the raw text.
          m = text.match(/\A\s*#(\S+)(.*)\z/m)
          return { menu_items: [], ghost: EMPTY_GHOST } unless m

          handle = m[1]
          after  = m[2]                     # everything after the handle chars
          ends_with_space = text.end_with?(" ")

          # No space after the handle yet → still typing the handle.
          return { menu_items: [], ghost: EMPTY_GHOST } unless after.match?(/\A\s/)

          after_words = after.split(/\s+/).reject(&:empty?)
          # Verb stage: nothing typed after the handle yet, or still typing the
          # first word (the action/verb).
          at_verb_stage = after_words.empty? || (after_words.size == 1 && !ends_with_space)
          partial = ends_with_space ? "" : (after_words.last || "")

          # Follow-up-aware: if this handle belongs to a live follow-up-able event,
          # suggest THAT target's actions (e.g. theme_list → preview/apply) rather
          # than the generic hashtag verbs. Falls through to the legacy path only
          # when the handle isn't a live follow-up.
          actions = follow_up_actions(handle, conversation)
          if actions
            return at_verb_stage ? follow_up_action_completions(actions, partial) : { menu_items: [], ghost: EMPTY_GHOST }
          end

          return hashtag_verb_completions(partial) if at_verb_stage

          # Metric stage (legacy hashtag-metric feature).
          hashtag_metric_completions(partial)
        end

        # Returns the declared action words for a live follow-up event carrying
        # `handle` in its reply_handle, or nil when the handle isn't a live
        # follow-up (so the caller falls back to the legacy hashtag path).
        def follow_up_actions(handle, conversation)
          return nil if handle.blank? || conversation.nil?

          event = conversation.events
            .where("payload->>'reply_handle' = ?", handle.to_s.downcase)
            .where("(payload->>'reply_consumed') IS NULL OR (payload->>'reply_consumed') = 'false'")
            .last
          return nil unless event

          Pito::FollowUp::Registry.actions_for(event.payload["reply_target"].to_s).presence
        end

        # Build completions for a follow-up handle's actions: a palette of all
        # actions plus an inline ghost (the first action, or the unique prefix
        # completion of the partial) so TAB accepts it.
        def follow_up_action_completions(actions, partial)
          menu_items = actions.map { |a| { label: a, insert: "#{a} ", description: "", masked: false } }

          ghost = if partial.empty?
                    { complete_current: actions.first.to_s, next_hint: "" }
          else
                    matches = actions.select { |a| a.to_s.start_with?(partial.downcase) }
                    completion = matches.size == 1 ? matches.first.to_s[partial.length..] : ""
                    { complete_current: completion, next_hint: "" }
          end

          { menu_items: menu_items, ghost: ghost }
        end

        def hashtag_verb_completions(partial)
          specs  = Pito::Grammar::Registry.specs(namespace: :hashtag)
          items  = specs
            .select { |s| s.name.to_s.start_with?(partial.downcase) }
            .map do |s|
              {
                label:       s.name.to_s,
                insert:      "#{s.name} ",
                description: description_for(s),
                masked:      false
              }
            end
          { menu_items: items, ghost: EMPTY_GHOST }
        end

        def hashtag_metric_completions(partial)
          vocab = Pito::Grammar::Registry.vocabulary(:metrics)
          return { menu_items: [], ghost: EMPTY_GHOST } unless vocab

          items = prefix_filter(vocab.canonical, partial).map do |member|
            { label: member, insert: "#{member} ", description: "", masked: false }
          end
          { menu_items: items, ghost: EMPTY_GHOST }
        end

        # ── FREE mode (ghost text, no palette) ───────────────────────────────

        def free_completions(text, authenticated:)
          tokens = Pito::Lex::Lexer.call(text)
          word_tokens = tokens.select { |t| t.type == :word }

          first_word = word_tokens.first&.value&.downcase&.to_sym
          return { menu_items: [], ghost: EMPTY_GHOST } unless first_word

          spec = Pito::Grammar::Registry.specs_for_alias(namespace: :chat, token: first_word)
          return { menu_items: [], ghost: EMPTY_GHOST } unless spec

          ghost = compute_ghost(text, spec, tokens, authenticated:)
          { menu_items: [], ghost: ghost }
        end

        # Compute ghost text for a matched chat spec.
        # complete_current: remaining chars if current partial uniquely prefixes a vocab member.
        # next_hint: slot-name hint when the cursor is at an empty token (trailing space).
        def compute_ghost(text, spec, tokens, authenticated:)
          ends_with_space = text.end_with?(" ")
          word_tokens     = tokens.select { |t| t.type == :word }

          # Slots that can provide completions.
          enum_slots = spec.slots.select { |s| s.kind == :enum }

          # Words typed so far (excluding the verb).
          typed_words = word_tokens.drop(1).map(&:value)

          # The current partial: last typed word (if not ending with space).
          current_partial = ends_with_space ? "" : typed_words.last.to_s

          # Track which slots have been consumed by the typed words.
          already_filled = {}
          words_to_consume = ends_with_space ? typed_words : typed_words.first(typed_words.size - 1)
          words_to_consume.each do |word|
            enum_slots.each do |slot|
              next if already_filled[slot.name] && !slot.repeatable?
              next unless slot.source.is_a?(Symbol)
              vocab = Pito::Grammar::Registry.vocabulary(slot.source)
              next unless vocab
              resolved = vocab.resolve(word.to_s.downcase)
              if resolved
                already_filled[slot.name] = true
                break
              end
            end
          end

          # Find the active slot — the first enum slot not yet fully consumed.
          active_slot = enum_slots.find do |s|
            !already_filled[s.name] || s.repeatable?
          end

          if ends_with_space
            # next_hint: provide a hint for the next expected slot.
            hint = next_hint_for_slot(active_slot)
            { complete_current: "", next_hint: hint }
          else
            # complete_current: if current partial uniquely prefixes one vocab member.
            completion = compute_current_completion(active_slot, current_partial, authenticated:)
            { complete_current: completion, next_hint: "" }
          end
        end

        def compute_current_completion(slot, partial, authenticated:)
          return "" if partial.empty? || slot.nil?
          return "" unless slot.source.is_a?(Symbol)

          vocab = Pito::Grammar::Registry.vocabulary(slot.source)
          return "" unless vocab

          candidates = if vocab.dynamic?
                         return "" if AUTH_GATED_VOCABS.include?(slot.source) && !authenticated

                         begin
                           vocab.members(context: partial)
                         rescue StandardError
                           []
                         end
          else
                         vocab.canonical
          end

          matches = candidates.select { |m| m.to_s.downcase.start_with?(partial.downcase) }

          # Only complete if exactly one match.
          return "" unless matches.size == 1

          matches.first.to_s[partial.length..]
        end

        def next_hint_for_slot(slot)
          return "" unless slot

          # Use a sample member if static, otherwise the slot name.
          if slot.source.is_a?(Symbol)
            vocab = Pito::Grammar::Registry.vocabulary(slot.source)
            if vocab && !vocab.dynamic? && vocab.canonical.any?
              return "<#{vocab.canonical.first}>"
            end
          end

          "<#{slot.name}>"
        end

        # ── Helpers ───────────────────────────────────────────────────────────

        # Returns members where the downcased member starts with downcased partial.
        # If partial is empty, returns all members.
        def prefix_filter(members, partial)
          return members if partial.to_s.empty?
          members.select { |m| m.to_s.downcase.start_with?(partial.downcase) }
        end

        def description_for(spec)
          return "" if spec.description_key.nil?

          I18n.t(spec.description_key)
        rescue StandardError
          ""
        end
      end
    end
  end
end
