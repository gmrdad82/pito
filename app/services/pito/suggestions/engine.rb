# frozen_string_literal: true

module Pito
  module Suggestions
    # Computes PALETTE suggestions for a given input and cursor position.
    #
    # call(input:, cursor:, conversation: nil, authenticated: false) →
    #   {
    #     mode:       Symbol (:slash | :hashtag | :free | :none),
    #     stage:      Symbol (:verb | :arg | :free | :none),
    #     menu_items: [ { label:, insert:, description:, masked: } ],
    #     ghost:      { complete_current:, next_hint: }   # always empty (kept for shape stability)
    #   }
    #
    # Suggestions are PALETTE-only. The inline free-chat "ghost"/typeahead and the
    # `tab` accept shortcut were removed (owner 2026-06-29): the `/slash` and
    # `#hashtag` selectable palettes are the only suggestion surfaces. `stage:
    # :verb` → the client renders menu_items as a browsable palette (slash verb
    # choice, the `/config` provider/key set, and the follow-up reply verbs).
    # FREE input and non-palette arg stages return empty. The `ghost` key is
    # retained as EMPTY_GHOST only to keep the response shape stable for clients.
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

          # Default stage per mode; slash/hashtag completion methods override it
          # explicitly (verb-stage → :verb palette, arg-stage → :arg ghost).
          default_stage = mode == :free ? :free : :none
          { mode: mode, stage: default_stage }.merge(result)
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
          return { menu_items: [], ghost: EMPTY_GHOST, stage: :arg } unless spec

          # Only `/config` offers arg suggestions — a small, browsable provider /
          # per-provider-key set surfaced as a selectable PALETTE (stage: :verb).
          # Every OTHER slash arg gets nothing: inline arg ghosts were removed
          # (owner 2026-06-29; the palette is the only slash suggestion surface).
          return { menu_items: [], ghost: EMPTY_GHOST, stage: :arg } unless spec.name == :config

          # The partial is everything after the last space ("" when text ends in " ").
          partial       = after_slash.end_with?(" ") ? "" : parts.last.to_s
          consumed_args = build_consumed_args(after_slash, partial)
          items         = arg_stage_completions(spec, consumed_args, partial, authenticated:)

          { menu_items: items, ghost: EMPTY_GHOST, stage: :verb }
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

          { menu_items: items, ghost: EMPTY_GHOST, stage: :verb }
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
              # KV args look like "key=value" or "key:value" — consume while present,
              # recording each supplied key so suggestions can exclude already-set ones.
              while remaining_args.any? && kv_arg?(remaining_args.first)
                key = remaining_args.first.to_s.split(/[=:]/, 2).first.to_s.downcase
                (resolved_values[slot.name] ||= []) << key
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

          # Typing a VALUE ("key=…") — the value is freeform, so there's nothing
          # to suggest. Returning [] empties the palette so Enter SUBMITS the
          # message instead of re-selecting the key being filled in.
          return [] if partial.present? && partial.include?("=")

          masked_keys = Pito::Grammar::Vocabularies::MASKED_CONFIG_KEYS
          already_set = Array(resolved_values[slot.name]).map { |k| k.to_s.downcase }

          provider = resolved_values[:provider].to_s.downcase
          candidate_keys = Pito::Grammar::Vocabularies.provider_keys(provider)
          # Fall back to the full vocab if the provider has no specific mapping.
          candidate_keys = vocab.canonical if candidate_keys.empty?

          # Drop keys already supplied, so a set option is never re-suggested and
          # the menu empties out once every option is provided (→ Enter submits).
          candidate_keys = candidate_keys.reject { |k| already_set.include?(k.to_s.downcase) }

          # Mid-typing a key → scope to the prefix.
          if partial.present?
            candidate_keys = candidate_keys.select { |k| k.to_s.downcase.start_with?(partial.downcase) }
          end

          candidate_keys.map do |key|
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

        # ── HASHTAG mode ─────────────────────────────────────────────────────

        def hashtag_completions(text, conversation: nil)
          # Input looks like "#handle verb metric". The handle can contain a
          # hyphen (e.g. follow-up handles `alpha-1266`), which the lexer would
          # split — so extract the full `#<handle>` directly from the raw text.
          m = text.match(/\A\s*#(\S+)(.*)\z/m)
          return { menu_items: [], ghost: EMPTY_GHOST, stage: :none } unless m

          handle = m[1]
          after  = m[2]                     # everything after the handle chars
          ends_with_space = text.end_with?(" ")

          # No space after the handle yet → still typing the handle.
          return { menu_items: [], ghost: EMPTY_GHOST, stage: :none } unless after.match?(/\A\s/)

          after_words = after.split(/\s+/).reject(&:empty?)
          # Verb stage: nothing typed after the handle yet, or still typing the
          # first word (the action/verb).
          at_verb_stage = after_words.empty? || (after_words.size == 1 && !ends_with_space)
          partial = ends_with_space ? "" : (after_words.last || "")

          # Follow-up-aware: if this handle belongs to a live follow-up-able event,
          # suggest THAT target's actions (e.g. game_list → show/delete) rather
          # than the generic hashtag verbs. Falls through to the legacy path only
          # when the handle isn't a live follow-up.
          actions, _target = follow_up_actions_with_target(handle, conversation)
          if actions
            # Verb stage → the reply-verb PALETTE. Arg stage → nothing (owner
            # 2026-06-29: inline arg suggestions/ghosts removed; the palette is the
            # only follow-up suggestion surface).
            return at_verb_stage ? follow_up_action_completions(actions, partial) : { menu_items: [], ghost: EMPTY_GHOST, stage: :arg }
          end

          return hashtag_verb_completions(partial) if at_verb_stage

          # Metric stage (legacy hashtag-metric feature).
          hashtag_metric_completions(partial)
        end

        # Returns [actions, reply_target] for a live follow-up event, or [nil, nil].
        #
        # Universal actions: share is ALWAYS appended; revoke/unshare are appended
        # only when a Share record exists for the event (i.e. the message has been
        # shared). This keeps the palette accurate: an un-shared message shows only
        # `share`; once shared it also shows `revoke`/`unshare`.
        def follow_up_actions_with_target(handle, conversation)
          return [ nil, nil ] if handle.blank? || conversation.nil?

          event = conversation.events
            .where("payload->>'reply_handle' = ?", handle.to_s.downcase)
            .where("(payload->>'reply_consumed') IS NULL OR (payload->>'reply_consumed') = 'false'")
            .last
          return [ nil, nil ] unless event

          target           = event.payload["reply_target"].to_s
          specific_actions = Pito::FollowUp::Registry.actions_for(target)

          # Universal share verbs for this event — none for a :confirmation message
          # (confirm/cancel only); else share always, + revoke/unshare when shared.
          share_verbs = Pito::Share::UniversalActions.verbs_for(event)

          all_actions = (specific_actions + share_verbs).uniq

          return [ nil, nil ] if all_actions.empty?

          filtered = specific_actions.present? ? filter_link_unlink(all_actions, event) : all_actions
          [ filtered, target ]
        end

        # Always offer both link and unlink for any target that declares them.
        # Previously this collapsed them to one based on link-state of a single
        # entity, but that was wrong for multi-target HABTM (the source could be
        # partially linked to some targets and not others).  Showing both lets
        # the user choose; gating (VerbDelegator) still permits both verbs.
        def filter_link_unlink(actions, _event)
          actions
        end

        # Build the reply-verb PALETTE for a follow-up handle's actions: all
        # actions, filtered by the typed verb prefix (so `wi` narrows to
        # with/without). stage: :verb → the client surfaces the whole list as a
        # selectable palette. (Inline ghost removed — owner 2026-06-29.)
        def follow_up_action_completions(actions, partial)
          matches    = partial.empty? ? actions : actions.select { |a| a.to_s.start_with?(partial.downcase) }
          menu_items = matches.map { |a| { label: a, insert: "#{a} ", description: "", masked: false } }

          { menu_items: menu_items, ghost: EMPTY_GHOST, stage: :verb }
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
          { menu_items: items, ghost: EMPTY_GHOST, stage: :verb }
        end

        def hashtag_metric_completions(partial)
          vocab = Pito::Grammar::Registry.vocabulary(:metrics)
          return { menu_items: [], ghost: EMPTY_GHOST } unless vocab

          items = prefix_filter(vocab.canonical, partial).map do |member|
            { label: member, insert: "#{member} ", description: "", masked: false }
          end
          { menu_items: items, ghost: EMPTY_GHOST, stage: :arg }
        end

        # ── FREE mode ────────────────────────────────────────────────────────

        # Free (natural-language) input gets NO suggestions (owner 2026-06-29:
        # inline free-chat typeahead removed — the `/slash` + `#hashtag` palettes
        # are the only suggestion surfaces). Kept as an explicit no-op so the
        # mode dispatch in `call` stays symmetric.
        def free_completions(_text, authenticated: false)
          { menu_items: [], ghost: EMPTY_GHOST }
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
