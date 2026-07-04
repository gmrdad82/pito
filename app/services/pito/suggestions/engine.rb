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
    # choice, the `/config` provider/key set, the follow-up reply verbs, and the
    # reply verbs' argument tokens — plan-0.9.5 E13). FREE input and non-palette
    # arg stages return empty. The `ghost` key is retained as EMPTY_GHOST only to
    # keep the response shape stable for clients.
    #
    # Tasks w + x:
    #   w — slash/hashtag/free mode detection + static slot resolution
    #   x — dynamic vocab resolution with auth-gating
    module Engine
      # Maximum number of dynamic VOCABULARY suggestions per query (game titles,
      # channels, conversations — sources that can grow large). The reply-handle
      # palette is deliberately uncapped (D11); this limit is not.
      DYNAMIC_LIMIT = 20

      # Auth-gated dynamic vocabulary names — never resolved for unauthenticated users.
      AUTH_GATED_VOCABS = %i[channels conversations].freeze

      # Reply-branch REF resolvers whose argument position is a list row id —
      # the arg-stage palette suggests the source list's "#N" tokens for these
      # (plan-0.9.5 E13). All three accept a "#N"-or-"N" ref (Dispatch::Resolvers).
      ROW_ID_REF_RESOLVERS = %w[id_among_rows video_by_id game_by_id].freeze

      # Per-entity ListColumns surface module — the same TARGET_META entity
      # projection Dispatch::ReplyBinding uses, mapped to the builder module
      # owning that surface's column/sort vocabulary (lambdas defer autoload,
      # mirroring ReplyBinding::COLUMN_VOCABULARY).
      ENTITY_LIST_COLUMNS = {
        "::Channel" => -> { Pito::MessageBuilder::Channel::ListColumns },
        "::Game"    => -> { Pito::MessageBuilder::Game::ListColumns },
        "::Video"   => -> { Pito::MessageBuilder::Video::ListColumns }
      }.freeze

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

          # plan-0.9.5 D5: slash commands list alphabetically
          items = filtered
            .select { |spec| spec.name.to_s.start_with?(partial.downcase) }
            .sort_by { |spec| spec.name.to_s }
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
            # plan-0.9.5 D5: enum/literal argument members list alphabetically
            prefix_filter(vocab.canonical, partial)
              .sort_by { |m| m.to_s.downcase }
              .map { |member| { label: member, insert: "#{member} ", description: "", masked: false } }
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

          # plan-0.9.5 D5: provider config keys list alphabetically (D5 overrides prior credentials-first semantic order)
          candidate_keys = candidate_keys.sort

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

          # plan-0.9.5 D5: bare `#` or `#partial` (no space typed yet) → show the
          # HANDLE palette: all live unconsumed reply handles, ordered by the source
          # event's created_at ASC (scrollback / conversation order).
          stripped = text.lstrip
          if stripped.match?(/\A#\S*\z/)
            partial = stripped.delete_prefix("#").downcase
            return reply_handle_completions(partial, conversation:)
          end

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
          actions, target, event = follow_up_actions_with_target(handle, conversation)
          if actions
            # Verb stage → the reply-verb PALETTE. Arg stage → the verb's possible
            # ARGUMENT tokens for this target (plan-0.9.5 E13).
            return follow_up_action_completions(actions, partial) if at_verb_stage

            committed = ends_with_space ? after_words.drop(1) : after_words[1..-2].to_a
            return follow_up_arg_completions(
              verb_token: after_words.first.to_s,
              committed:  committed,
              partial:    partial,
              target:     target,
              event:      event
            )
          end

          return hashtag_verb_completions(partial) if at_verb_stage

          # Metric stage (legacy hashtag-metric feature).
          hashtag_metric_completions(partial)
        end

        # Returns [actions, reply_target, event] for a live follow-up event, or
        # [nil, nil, nil].
        #
        # Universal actions: share is ALWAYS appended; revoke/unshare are appended
        # only when a Share record exists for the event (i.e. the message has been
        # shared). This keeps the palette accurate: an un-shared message shows only
        # `share`; once shared it also shows `revoke`/`unshare`.
        def follow_up_actions_with_target(handle, conversation)
          return [ nil, nil, nil ] if handle.blank? || conversation.nil?

          event = conversation.events
            .where("payload->>'reply_handle' = ?", handle.to_s.downcase)
            .where("(payload->>'reply_consumed') IS NULL OR (payload->>'reply_consumed') = 'false'")
            .last
          return [ nil, nil, nil ] unless event

          target           = event.payload["reply_target"].to_s
          specific_actions = Pito::FollowUp::Registry.actions_for(target)

          # Universal share verbs for this event — none for a :confirmation message
          # (confirm/cancel only); else share always, + revoke/unshare when shared.
          share_verbs = Pito::Share::UniversalActions.verbs_for(event)

          all_actions = (specific_actions + share_verbs).uniq

          return [ nil, nil, nil ] if all_actions.empty?

          filtered = specific_actions.present? ? filter_link_unlink(all_actions, event) : all_actions
          [ filtered, target, event ]
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
          # plan-0.9.5 D5: follow-up reply verbs list alphabetically
          matches    = partial.empty? ? actions : actions.select { |a| a.to_s.start_with?(partial.downcase) }
          matches    = matches.sort_by { |a| a.to_s }
          menu_items = matches.map { |a| { label: a, insert: "#{a} ", description: "", masked: false } }

          { menu_items: menu_items, ghost: EMPTY_GHOST, stage: :verb }
        end

        # ── Follow-up ARG stage (plan-0.9.5 E13) ─────────────────────────────

        # After `#handle <verb> ` (and mid-arg-token) the palette suggests the
        # verb's possible ARGUMENT tokens for the source message's reply_target.
        # Config-driven: the verb's declared reply branch (config/pito/verbs.yml,
        # read via Pito::Dispatch::ReplyBinding.target_config) names the ref/args
        # resolvers, and each suggestible resolver maps to its vocabulary:
        #
        #   ref in ROW_ID_REF_RESOLVERS → the source list's row ids ("#N")
        #   column_list                 → the surface's column tokens (addable
        #                                 for `with`, removable for `without` —
        #                                 the same derivation as options_footer)
        #   sort_clause                 → the surface's sort keys
        #   metric_list                 → metric tokens (:metrics vocabulary —
        #                                 the hashtag_metric_completions precedent)
        #   visit_destination           → the :visit_destinations vocabulary
        #
        # Freeform resolvers (amounts, when-phrases, link targets) and no-arg
        # verbs (e.g. `next`) suggest nothing — the empty menu keeps Enter
        # submitting. A non-empty menu is tagged stage: :verb so the client
        # renders it as a browsable palette (the /config arg-stage precedent).
        def follow_up_arg_completions(verb_token:, committed:, partial:, target:, event:)
          verb   = Pito::Dispatch::Matrix.verb_for(verb_token.downcase) || verb_token.downcase
          config = Pito::Dispatch::ReplyBinding.target_config(verb, target)
          return { menu_items: [], ghost: EMPTY_GHOST, stage: :arg } unless config

          labels = reply_arg_labels(verb:, config:, committed:, partial:, target:, event:)
          items  = labels.map { |l| { label: l, insert: "#{l} ", description: "", masked: false } }

          { menu_items: items, ghost: EMPTY_GHOST, stage: items.empty? ? :arg : :verb }
        end

        # Ordered labels for the active argument position. A row-id ref owns the
        # FIRST position (the interleaved `<id> <value>` reply shape —
        # ReplyBinding::LEADING_TOKEN_REFS); the declared args take over after it.
        def reply_arg_labels(verb:, config:, committed:, partial:, target:, event:)
          if ROW_ID_REF_RESOLVERS.include?(config.dig(:ref, :resolver).to_s)
            return row_id_labels(event, partial) if committed.empty?

            committed = committed.drop(1)
          end

          resolver = (config[:args] || {}).values.first.to_h[:resolver].to_s
          candidates =
            case resolver
            when "column_list"       then column_candidates(verb, committed, target, event)
            when "sort_clause"       then sort_key_candidates(committed, target, event)
            when "metric_list"       then metric_candidates(committed)
            when "visit_destination" then destination_candidates(committed)
            when "price_amount"      then price_amount_candidates(committed)
            else []
            end

          # plan-0.9.5 D5: argument vocabularies list alphabetically.
          prefix_filter(candidates, partial).sort_by { |c| c.to_s.downcase }
        end

        # The source list's row ids as "#N" labels — numeric ascending (ids are
        # the rows' canonical order; alphabetical over "#N" strings would put
        # "#10" between "#1" and "#2"), capped at DYNAMIC_LIMIT. A typed partial
        # matches with or without its leading "#".
        def row_id_labels(event, partial)
          ids = Array(event.payload["table_rows"]).filter_map { |row| row_id_for(row) }
          ids = ids.uniq.sort.first(DYNAMIC_LIMIT)

          wanted = partial.to_s.delete_prefix("#")
          ids = ids.select { |id| id.to_s.start_with?(wanted) } unless wanted.empty?

          ids.map { |id| "##{id}" }
        end

        # A row's leading id — the first cell's "#N" text (or the legacy key
        # form), mirroring the :id_among_rows resolver's extraction.
        def row_id_for(row)
          return nil unless row.is_a?(Hash)

          first_cell = Array(row["cells"] || row[:cells]).first
          text = first_cell.is_a?(Hash) ? (first_cell["text"] || first_cell[:text]) : (row["key"] || row[:key])
          digits = text.to_s.sub(/\A#\s*/, "")
          digits.to_i if digits.match?(/\A\d+\z/)
        end

        # Column tokens for a `with`/`without` reply on a list surface — the
        # same derivation the list's options footer uses: addable (declared
        # minus visible) for `with`, removable (visible) for `without`, minus
        # tokens already typed in this reply. Labels are display tokens.
        def column_candidates(verb, committed, target, event)
          list_columns = list_columns_for(target)
          return [] unless list_columns.respond_to?(:vocabulary)

          current = Array(event.payload["list_columns"]).map(&:to_sym)
          vocab   = list_columns.vocabulary
          typed   = committed.filter_map { |t| vocab[t.to_s.downcase] }

          canonicals = verb == "without" ? current : (list_columns::COLUMNS.keys - current)
          (canonicals - typed).map { |c| list_columns.display_token(c) }
        end

        # Sort-key tokens for a `sort`/`order` reply — the surface's sortable
        # tokens (the fixed set for channels; base + visible columns' primary
        # aliases for game/video, the options_footer derivation). Offered only
        # while the column token is unchosen; the leading `by` particle is
        # transparent.
        def sort_key_candidates(committed, target, event)
          effective = committed.first.to_s.downcase == "by" ? committed.drop(1) : committed
          return [] unless effective.empty?

          list_columns = list_columns_for(target)
          return [] if list_columns.nil?
          return list_columns.sortable_tokens if list_columns.respond_to?(:sortable_tokens)

          current = Array(event.payload["list_columns"]).map(&:to_sym)
          list_columns.base_sort_tokens + current.filter_map { |c| list_columns::SORT_VOCAB.key(c) }
        end

        # Metric tokens for a `with`/`without` reply on an analyze surface — the
        # :metrics vocabulary (the same source hashtag_metric_completions uses),
        # minus metrics already typed in this reply (aliases resolved).
        def metric_candidates(committed)
          vocab = Pito::Grammar::Registry.vocabulary(:metrics)
          return [] unless vocab

          typed = committed.filter_map { |t| vocab.resolve(t.to_s) }
          vocab.canonical.reject { |m| typed.include?(m) }
        end

        # Leading tokens for a `price` reply (`price [set] <amount>` /
        # `price unset`) — the amount itself is free-form, but `set`/`unset`
        # are its enumerable openers (owner G31). First position only.
        def price_amount_candidates(committed)
          return [] unless committed.empty?

          %w[set unset]
        end

        # Destination tokens for a `visit` reply — the :visit_destinations
        # vocabulary, offered only for the first argument position.
        def destination_candidates(committed)
          return [] unless committed.empty?

          vocab = Pito::Grammar::Registry.vocabulary(:visit_destinations)
          vocab ? vocab.canonical : []
        end

        # The ListColumns surface module for a reply target (nil when the
        # target's entity has no list surface).
        def list_columns_for(target)
          entity   = Pito::Dispatch::ReplyBinding::TARGET_META.dig(target.to_s, :entity)
          provider = ENTITY_LIST_COLUMNS[entity]
          provider&.call
        end

        def hashtag_verb_completions(partial)
          specs  = Pito::Grammar::Registry.specs(namespace: :hashtag)
          # plan-0.9.5 D5: hashtag (chat-namespace) verb completions list alphabetically
          items  = specs
            .select  { |s| s.name.to_s.start_with?(partial.downcase) }
            .sort_by { |s| s.name.to_s }
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

          # plan-0.9.5 D5: metric argument members list alphabetically
          items = prefix_filter(vocab.canonical, partial)
            .sort_by { |m| m.to_s.downcase }
            .map { |member| { label: member, insert: "#{member} ", description: "", masked: false } }
          { menu_items: items, ghost: EMPTY_GHOST, stage: :arg }
        end

        # ── FREE mode ────────────────────────────────────────────────────────

        # Free (natural-language) input: produces PALETTE suggestions for chat
        # verb enum slots once the verb token is committed (a space has been typed).
        #
        # Ghost text was removed (owner 2026-06-29); only menu_items are populated.
        # Slash/hashtag palettes are unchanged.
        #
        # Stage logic (plan-0.9.5 E8/D5):
        #   - Verb not yet committed (no space) → empty.
        #   - Verb not in :chat namespace → empty.
        #   - Introducer word typed (e.g. "with", "only", "for") → suggest the
        #     matching slot's vocabulary members.
        #   - Otherwise → suggest non-introduced enum slots' members plus the
        #     introducer keywords themselves (palette entries for the user to
        #     select the branch they want next).
        def free_completions(text, authenticated: false)
          stripped  = text.lstrip
          space_idx = stripped.index(" ")
          return { menu_items: [], ghost: EMPTY_GHOST } unless space_idx

          verb_token = stripped[0...space_idx].downcase.to_sym
          spec = Pito::Grammar::Registry.specs_for_alias(namespace: :chat, token: verb_token)
          return { menu_items: [], ghost: EMPTY_GHOST } unless spec

          ends_with_space  = text.end_with?(" ")
          after_verb_words = stripped[space_idx..].split
          partial          = ends_with_space ? "" : (after_verb_words.last || "")
          typed_tokens     = ends_with_space ? after_verb_words : after_verb_words[0..-2]

          items = chat_verb_completions(spec, typed_tokens.to_a, partial, authenticated:)
          return { menu_items: [], ghost: EMPTY_GHOST } if items.empty?

          { menu_items: items, ghost: EMPTY_GHOST, stage: :verb }
        end

        # Builds palette menu_items for a free-mode chat verb at the current
        # typing stage.
        #
        # typed_tokens — tokens the user has fully committed after the verb
        #                (everything before the current partial).
        # partial      — token currently being typed ("" when text ends with
        #                a space).
        #
        # Only :enum / :literal slots with a Symbol source are suggestable;
        # :free, :kv, and :connective slots carry no completion vocabulary.
        #
        # Introducer logic:
        #   If the most recently committed introducer keyword (e.g. "with",
        #   "only", "for") appears in typed_tokens, suggest the matching slot's
        #   vocabulary members.  Otherwise, suggest non-introduced slots' members
        #   PLUS the introducer keywords themselves as selectable items so the
        #   user sees the gated branches they can enter.
        def chat_verb_completions(spec, typed_tokens, partial, authenticated:)
          suggestable_slots = spec.slots.select do |s|
            (s.kind == :enum || s.kind == :literal) && s.source.is_a?(Symbol)
          end
          return [] if suggestable_slots.empty?

          # G37 — a :free slot (the `#id` position on `show`) is a POSITIONAL
          # GATE: slots declared after it stay unsuggested until an id-looking
          # token fills it, so following the palette can never compose
          # "show game full" with the id silently skipped. Noun tokens don't
          # fill the gate (they're structural, not the ref); the palette's
          # silence at the gap IS the reserved place.
          gate_idx = free_gate_index(spec, typed_tokens)

          # Walk the committed tokens, FILLING slots as they match (G32 — the
          # old walk only tracked introducers, so `ls games ` re-offered the
          # noun vocabulary forever instead of advancing). An introducer
          # keyword opens its slot; any other token resolves against the open
          # introduced slot first, then the open plain slots in declaration
          # order (aliases resolve: "vid" fills :nouns as "vids"). Repeatable
          # slots stay open — their committed members are excluded from the
          # suggestions instead. Unresolvable tokens (titles, ids, amounts)
          # fill nothing and cost nothing.
          filled = {}
          active = nil
          typed_tokens.each do |raw|
            token = raw.downcase.delete_suffix(",")
            if (intro = suggestable_slots.find { |s| s.introducer && s.introducer.to_s == token })
              active = intro
              next
            end

            slot = resolving_slot(active, suggestable_slots, filled, token)
            next unless slot

            (filled[slot] ||= []) << Pito::Grammar::Registry.vocabulary(slot.source).resolve(token)
            active = nil if active == slot && !slot.repeatable
          end

          # Inside an introduced slot → its remaining members only (an entered
          # introducer implies the user already crossed the gate deliberately).
          if active
            committed = Array(filled[active]).map(&:to_s)
            return suggest_for_slot(active, partial, authenticated:)
                     .reject { |i| committed.include?(i[:label].to_s) }
          end

          # General position: open plain slots' remaining members, plus the
          # introducer keywords of slots that can still take (more) values —
          # but nothing declared BEYOND an unfilled :free gate (G37).
          items = []
          suggestable_slots.each do |slot|
            next if gate_idx && spec.slots.index(slot) > gate_idx

            closed = !slot.repeatable && Array(filled[slot]).any?
            next if closed

            if slot.introducer
              intro = slot.introducer.to_s
              if partial.empty? || intro.start_with?(partial.downcase)
                items << { label: intro, insert: "#{intro} ", description: "", masked: false }
              end
            else
              committed = Array(filled[slot]).map(&:to_s)
              items.concat(
                suggest_for_slot(slot, partial, authenticated:)
                  .reject { |i| committed.include?(i[:label].to_s) }
              )
            end
          end

          # The `list` verb's kwargs (with-columns, sort clause, filters) are
          # RAW-parsed by its handler, not verbs.yml slots — the slot walk
          # can't see them, so a filled noun went silent (owner G33: "full
          # kwargs support"). Suggest the clause the cursor is inside.
          items.concat(list_kwarg_completions(typed_tokens, partial)) if spec.name == :list

          # plan-0.9.5 D5: list alphabetically; deduplicate by label.
          items.sort_by { |i| i[:label].to_s.downcase }.uniq { |i| i[:label] }
        end

        # ── free-mode `list` kwargs (G33) ─────────────────────────────────────

        # The list surfaces' column modules, keyed by canonical noun — the
        # same single-source vocabularies the tables and footers render from.
        LIST_SURFACES = {
          "games"    => Pito::MessageBuilder::Game::ListColumns,
          "vids"     => Pito::MessageBuilder::Video::ListColumns,
          "channels" => Pito::MessageBuilder::Channel::ListColumns
        }.freeze

        SORT_KEYWORDS = %w[sort sorted order ordered].freeze

        # Noun-specific single-token filters the list handler raw-parses.
        LIST_FILTER_TOKENS = {
          "games" => %w[upcoming],
          "vids"  => %w[published unlisted scheduled]
        }.freeze

        # Completions for the clause the cursor sits in:
        #   after the noun     → the kwarg openers (with, sorted by, filters)
        #   inside `with …`    → the surface's remaining addable columns
        #   inside `sort [by]` → sortable tokens (base + with-selected), then asc/desc
        def list_kwarg_completions(typed_tokens, partial)
          nouns = Pito::Grammar::Registry.vocabulary(:nouns)
          return [] unless nouns

          noun_idx = typed_tokens.index { |t| nouns.resolve(t.downcase) }
          return [] unless noun_idx

          noun    = nouns.resolve(typed_tokens[noun_idx].downcase)
          surface = LIST_SURFACES[noun]
          return [] unless surface

          rest = typed_tokens[(noun_idx + 1)..].map { |t| t.downcase.delete_suffix(",") }

          with_idx = rest.rindex("with")
          sort_idx = rest.rindex { |t| SORT_KEYWORDS.include?(t) }

          candidates =
            if sort_idx && (!with_idx || sort_idx > with_idx)
              sort_clause_candidates(rest, sort_idx, with_idx, surface)
            elsif with_idx
              with_clause_candidates(rest, with_idx, surface)
            else
              [ "with", "sorted by" ] + LIST_FILTER_TOKENS.fetch(noun, []) - rest
            end

          prefix_filter(candidates, partial)
            .sort_by { |c| c.to_s.downcase }
            .map { |label| { label: label, insert: "#{label} ", description: "", masked: false } }
        end

        # Remaining addable columns after the ones already typed in the clause.
        def with_clause_candidates(rest, with_idx, surface)
          committed = rest[(with_idx + 1)..].filter_map { |t| surface.vocabulary[t] }
          (surface::COLUMNS.keys - committed).map { |c| column_display_token(surface, c) }
        end

        # Sort tokens while the column is unchosen; asc/desc once it is.
        def sort_clause_candidates(rest, sort_idx, with_idx, surface)
          after = rest[(sort_idx + 1)..]
          after = after.drop(1) if after.first == "by"

          case after.size
          when 0
            selected = if with_idx && with_idx < sort_idx
              rest[(with_idx + 1)...sort_idx].filter_map { |t| surface.vocabulary[t] }
            else
              []
            end
            sortable_tokens_for(surface, selected)
          when 1 then %w[asc desc]
          else []
          end
        end

        # Sortable tokens per surface: channels expose the derivation directly;
        # game/video mirror their options footers (base + visible with-columns).
        def sortable_tokens_for(surface, selected)
          return surface.sortable_tokens(selected_columns: selected) if surface.respond_to?(:sortable_tokens)

          surface.base_sort_tokens + selected.filter_map { |c| surface::SORT_VOCAB.key(c) }
        end

        # Channel::ListColumns has no display_token — fall back to the first alias.
        def column_display_token(surface, canonical)
          return surface.display_token(canonical) if surface.respond_to?(:display_token)

          surface::COLUMNS.fetch(canonical)[:aliases].first
        end

        # The index of the first UNFILLED :free slot (the G37 gate), or nil
        # when there is none / it's already filled. A token fills the gate when
        # no vocabulary resolves it AND it isn't a noun — ids ("5", "#1"),
        # @handles, and titles qualify; "game"/"vids" don't.
        def free_gate_index(spec, typed_tokens)
          gate = spec.slots.find { |s| s.kind == :free }
          return nil unless gate

          nouns  = Pito::Grammar::Registry.vocabulary(:nouns)
          vocabs = spec.slots.filter_map { |s| s.source.is_a?(Symbol) ? Pito::Grammar::Registry.vocabulary(s.source) : nil }
          introducers = spec.slots.filter_map { |s| s.introducer&.to_s }

          filled = typed_tokens.any? do |raw|
            token = raw.downcase.delete_suffix(",")
            next false if introducers.include?(token)
            next false if nouns&.resolve(token)
            next false if vocabs.any? { |v| v.resolve(token) }

            true
          end

          filled ? nil : spec.slots.index(gate)
        end

        # The slot a committed token fills: the open introduced slot when its
        # vocabulary resolves the token, else the first open plain slot that
        # resolves it. nil when nothing matches (free text never fills a slot).
        def resolving_slot(active, slots, filled, token)
          candidates = active ? [ active ] : slots.reject(&:introducer)
          candidates.find do |slot|
            next false unless slot.repeatable || Array(filled[slot]).empty?

            Pito::Grammar::Registry.vocabulary(slot.source)&.resolve(token)
          end
        end

        # ── Helpers ───────────────────────────────────────────────────────────

        # plan-0.9.5 D5/D11: reply-HANDLE palette — fires while the user is still
        # typing the handle token (bare `#` or `#partial`, no space yet).
        # Lists ALL live (unconsumed) reply handles ordered by their source event's
        # created_at ASC (scrollback reading order). No cap: every new message
        # consumes/clears prior handles so the live set cannot grow unbounded
        # (owner ruling, plan-0.9.5 D11).
        def reply_handle_completions(partial, conversation: nil)
          return { menu_items: [], ghost: EMPTY_GHOST, stage: :verb } if conversation.nil?

          handles = conversation.events
            .where("payload->>'reply_handle' IS NOT NULL")
            .where("(payload->>'reply_consumed') IS NULL OR (payload->>'reply_consumed') = 'false'")
            .order(created_at: :asc)
            .pluck(Arel.sql("payload->>'reply_handle'"))
            .uniq
            .compact

          # Prefix-filter: a typed prefix scopes to matching live handles.
          # Result stays in ASC (scrollback) order.
          candidates = partial.empty? ? handles : handles.select { |h| h.start_with?(partial) }

          items = candidates.map do |handle|
            { label: "##{handle}", insert: "##{handle} ", description: "", masked: false }
          end

          { menu_items: items, ghost: EMPTY_GHOST, stage: :verb }
        end

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
