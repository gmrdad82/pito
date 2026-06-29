# frozen_string_literal: true

module Pito
  module Suggestions
    # Computes autocomplete suggestions for a given input and cursor position.
    #
    # call(input:, cursor:, conversation: nil, authenticated: false) →
    #   {
    #     mode:       Symbol (:slash | :hashtag | :free | :none),
    #     stage:      Symbol (:verb | :arg | :free | :none),
    #     menu_items: [ { label:, insert:, description:, masked: } ],
    #     ghost:      { complete_current:, next_hint: }
    #   }
    #
    # `stage` tells the client how to surface menu_items: :verb → render the
    # whole list as a selectable PALETTE (slash/hashtag verb choice, incl. the
    # follow-up reply verbs); :arg → show only the top hit as an inline GHOST.
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

          # The partial is everything after the last space.
          # If text ends with " ", partial is "".
          partial = after_slash.end_with?(" ") ? "" : parts.last.to_s

          # Already-consumed arg tokens (everything between verb and partial).
          # We need to figure out which slot is active.
          consumed_args = build_consumed_args(after_slash, partial)

          items = arg_stage_completions(spec, consumed_args, partial, authenticated:)
          ghost = kv_ghost_for(spec, consumed_args, partial)

          # `/config` arg slots (the provider vocab and per-provider kv keys) are a
          # small, browsable set — surface them as a selectable PALETTE (stage:
          # :verb) so the client renders the whole list, not just the top hit as an
          # inline ghost. Scoped to :config so other slash args (e.g. `/games
          # import`) keep the inline-ghost arg treatment.
          stage = config_arg_palette?(spec, items) ? :verb : :arg
          { menu_items: items, ghost: ghost, stage: stage }
        end

        # True when the active completion belongs to a `/config` argument slot
        # (provider vocab or per-provider kv keys) and there is at least one item
        # to show — the signal that the client should render a browsable palette.
        def config_arg_palette?(spec, items)
          spec.name == :config && items.any?
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

        # ── KV ghost ────────────────────────────────────────────────────────

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
          actions, target = follow_up_actions_with_target(handle, conversation)
          if actions
            if at_verb_stage
              return follow_up_action_completions(actions, partial)
            else
              # Arg stage: for game_list/video_list with/without, ghost column tokens.
              action = after_words.first&.downcase
              if %w[with without].include?(action) && %w[game_list video_list].include?(target)
                # args_text = everything after "#<handle> <action> " (the comma-list).
                args_text = after.lstrip.sub(/\A\S+\s+/, "")
                result = Pito::Suggestions::ListClauseGhost.hashtag_list_action_completions(
                  target, args_text, ends_with_space
                )
                return result.merge(stage: :arg) if result
              end

              # Arg stage: for game_list/video_list sort/order, ghost sort column tokens.
              if %w[sort order].include?(action) && %w[game_list video_list].include?(target)
                # args_text = everything after "#<handle> <action> " (the sort clause).
                args_text    = after.lstrip.sub(/\A\S+\s*/, "")
                list_columns = follow_up_event_list_columns(handle, conversation)
                result = Pito::Suggestions::ListClauseGhost.hashtag_list_sort_completions(
                  target,
                  list_columns:,
                  args_text:,
                  ends_with_space:
                )
                return result.merge(stage: :arg) if result
              end

              # Arg stage: for schedule, surface the `slate` keyword (the
              # next-open-slot alternative to an explicit <when>) the same way
              # other static-vocab options are offered.
              if action == "schedule" && Pito::FollowUp::Registry.actions_for(target).include?("schedule")
                result = hashtag_schedule_arg_completions(partial)
                return result.merge(stage: :arg) if result
              end

              # Arg stage: for price, surface the `set`/`unset` subcommand — but ONLY
              # at the subcommand position (`price <here>`), not after it (the id +
              # amount that follow are free, no suggestion).
              if action == "price" && Pito::FollowUp::Registry.actions_for(target).include?("price")
                at_subcommand = (after_words.length == 1 && ends_with_space) ||
                                (after_words.length == 2 && !ends_with_space)
                if at_subcommand
                  result = hashtag_price_arg_completions(partial)
                  return result.merge(stage: :arg) if result
                end
              end

              # Arg stage: for platform, surface the `set`/`unset` subcommand — same
              # subcommand-position rule as price (the id + name that follow are free).
              if action == "platform" && Pito::FollowUp::Registry.actions_for(target).include?("platform")
                at_subcommand = (after_words.length == 1 && ends_with_space) ||
                                (after_words.length == 2 && !ends_with_space)
                if at_subcommand
                  result = hashtag_platform_arg_completions(partial)
                  return result.merge(stage: :arg) if result
                end
              end

              # Arg stage: for visit (channel_detail), surface `channel`/`studio`
              # destination — same subcommand-position rule as price/platform.
              if action == "visit" && Pito::FollowUp::Registry.actions_for(target).include?("visit")
                at_subcommand = (after_words.length == 1 && ends_with_space) ||
                                (after_words.length == 2 && !ends_with_space)
                if at_subcommand
                  result = hashtag_visit_arg_completions(partial)
                  return result.merge(stage: :arg) if result
                end
              end

              # Fallback: offer --help ghost when the partial starts with "-".
              return hashtag_arg_help_completions(partial).merge(stage: :arg)
            end
          end

          return hashtag_verb_completions(partial) if at_verb_stage

          # Metric stage (legacy hashtag-metric feature).
          hashtag_metric_completions(partial)
        end

        # Returns the declared action words for a live follow-up event carrying
        # `handle` in its reply_handle, or nil when the handle isn't a live
        # follow-up (so the caller falls back to the legacy hashtag path).
        def follow_up_actions(handle, conversation)
          actions, _target = follow_up_actions_with_target(handle, conversation)
          actions
        end

        # Returns [actions, reply_target] for a live follow-up event, or [nil, nil].
        #
        # Universal actions (share/revoke/unshare) are ALWAYS appended when a live
        # follow-up event is found, even when the reply_target has no registered
        # handler or no specific actions. This surfaces share affordances on every
        # repliable message without requiring each handler to declare them.
        def follow_up_actions_with_target(handle, conversation)
          return [ nil, nil ] if handle.blank? || conversation.nil?

          event = conversation.events
            .where("payload->>'reply_handle' = ?", handle.to_s.downcase)
            .where("(payload->>'reply_consumed') IS NULL OR (payload->>'reply_consumed') = 'false'")
            .last
          return [ nil, nil ] unless event

          target           = event.payload["reply_target"].to_s
          specific_actions = Pito::FollowUp::Registry.actions_for(target)

          # Universal actions (share/revoke/unshare) work on ANY reply_handle event.
          # Always append them so the autosuggest surfaces them for every shareable message.
          all_actions = (specific_actions + Pito::Share::UniversalActions::VERBS).uniq

          return [ nil, nil ] if all_actions.empty?

          filtered = specific_actions.present? ? filter_link_unlink(all_actions, event) : all_actions
          [ filtered, target ]
        end

        # Returns the list_columns array from the live follow-up event payload for
        # the given handle, or [] when the event cannot be found or has no list_columns.
        def follow_up_event_list_columns(handle, conversation)
          return [] if handle.blank? || conversation.nil?

          event = conversation.events
            .where("payload->>'reply_handle' = ?", handle.to_s.downcase)
            .where("(payload->>'reply_consumed') IS NULL OR (payload->>'reply_consumed') = 'false'")
            .last
          return [] unless event

          Array(event.payload["list_columns"])
        end

        # Always offer both link and unlink for any target that declares them.
        # Previously this collapsed them to one based on link-state of a single
        # entity, but that was wrong for multi-target HABTM (the source could be
        # partially linked to some targets and not others).  Showing both lets
        # the user choose; gating (VerbDelegator) still permits both verbs.
        def filter_link_unlink(actions, _event)
          actions
        end

        # Build completions for a follow-up handle's actions: a palette of all
        # actions plus an inline ghost (the first action, or the unique prefix
        # completion of the partial) so TAB accepts it.
        # When the partial starts with "-" and prefixes "--help", returns the
        # --help ghost/menu item instead of action completions (mirrors free-mode
        # engine.rb:563-566).
        def follow_up_action_completions(actions, partial)
          # --help ghost: any partial starting with "-" that prefixes "--help".
          if partial.start_with?("-") && "--help".start_with?(partial.downcase)
            return hashtag_arg_help_completions(partial).merge(stage: :arg)
          end

          # Filter the palette by the typed verb prefix (mirrors the slash verb
          # palette) so the menu narrows as the user types `wi` → with/without.
          matches    = partial.empty? ? actions : actions.select { |a| a.to_s.start_with?(partial.downcase) }
          menu_items = matches.map { |a| { label: a, insert: "#{a} ", description: "", masked: false } }

          ghost = if partial.empty?
                    { complete_current: actions.first.to_s, next_hint: "" }
          else
                    completion = matches.size == 1 ? matches.first.to_s[partial.length..] : ""
                    { complete_current: completion, next_hint: "" }
          end

          # :verb → the client surfaces ALL menu_items as a selectable palette
          # (with/without/shinies/schedule/show/…), not just the top ghost.
          { menu_items: menu_items, ghost: ghost, stage: :verb }
        end

        # Arg-stage completions for `#<handle> schedule …`: surface the `slate`
        # keyword (the next-open-slot alternative to an explicit <when>) from the
        # :schedule_whens vocab, mirroring hashtag_metric_completions. Returns nil
        # when the partial prefixes no schedule keyword so the caller can fall
        # through to the --help ghost.
        def hashtag_schedule_arg_completions(partial)
          vocab = Pito::Grammar::Registry.vocabulary(:schedule_whens)
          return nil unless vocab

          members = prefix_filter(vocab.canonical, partial)
          return nil if members.empty?

          menu_items = members.map do |member|
            { label: member, insert: "#{member} ", description: "", masked: false }
          end

          ghost =
            if partial.empty?
              { complete_current: members.first.to_s, next_hint: "" }
            elsif members.size == 1
              { complete_current: members.first.to_s[partial.length..], next_hint: "" }
            else
              EMPTY_GHOST
            end

          { menu_items: menu_items, ghost: ghost }
        end

        # `set`/`unset` subcommand completions for `#<handle> price …` — mirrors
        # hashtag_schedule_arg_completions but over the price_subcommands vocab.
        def hashtag_price_arg_completions(partial)
          vocab = Pito::Grammar::Registry.vocabulary(:price_subcommands)
          return nil unless vocab

          members = prefix_filter(vocab.canonical, partial)
          return nil if members.empty?

          menu_items = members.map do |member|
            { label: member, insert: "#{member} ", description: "", masked: false }
          end

          ghost =
            if partial.empty?
              { complete_current: members.first.to_s, next_hint: "" }
            elsif members.size == 1
              { complete_current: members.first.to_s[partial.length..], next_hint: "" }
            else
              EMPTY_GHOST
            end

          { menu_items: menu_items, ghost: ghost }
        end

        # `channel`/`studio` destination completions for `#<handle> visit …` (channel_detail
        # cards) — mirrors hashtag_price_arg_completions over the visit_destinations vocab.
        def hashtag_visit_arg_completions(partial)
          vocab = Pito::Grammar::Registry.vocabulary(:visit_destinations)
          return nil unless vocab

          members = prefix_filter(vocab.canonical, partial)
          return nil if members.empty?

          menu_items = members.map do |member|
            { label: member, insert: "#{member} ", description: "", masked: false }
          end

          ghost =
            if partial.empty?
              { complete_current: members.first.to_s, next_hint: "" }
            elsif members.size == 1
              { complete_current: members.first.to_s[partial.length..], next_hint: "" }
            else
              EMPTY_GHOST
            end

          { menu_items: menu_items, ghost: ghost }
        end

        # `set`/`unset` subcommand completions for `#<handle> platform …` — mirrors
        # hashtag_price_arg_completions over the platform_subcommands vocab.
        def hashtag_platform_arg_completions(partial)
          vocab = Pito::Grammar::Registry.vocabulary(:platform_subcommands)
          return nil unless vocab

          members = prefix_filter(vocab.canonical, partial)
          return nil if members.empty?

          menu_items = members.map do |member|
            { label: member, insert: "#{member} ", description: "", masked: false }
          end

          ghost =
            if partial.empty?
              { complete_current: members.first.to_s, next_hint: "" }
            elsif members.size == 1
              { complete_current: members.first.to_s[partial.length..], next_hint: "" }
            else
              EMPTY_GHOST
            end

          { menu_items: menu_items, ghost: ghost }
        end

        # Returns a --help ghost + menu item when `partial` starts with "-" and
        # prefixes "--help".  Used in both verb-stage and arg-stage hashtag paths.
        # Returns EMPTY_GHOST when the partial doesn't qualify.
        def hashtag_arg_help_completions(partial)
          if partial.start_with?("-") && "--help".start_with?(partial.downcase)
            completion = "--help"[partial.length..]
            help_item  = { label: "--help", insert: "--help ", description: "Print this help message", masked: false }
            { menu_items: [ help_item ], ghost: { complete_current: completion, next_hint: "" } }
          else
            { menu_items: [], ghost: EMPTY_GHOST }
          end
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

        # ── FREE mode (ghost text, no palette) ───────────────────────────────

        def free_completions(text, authenticated:)
          tokens = Pito::Lex::Lexer.call(text)
          word_tokens = tokens.select { |t| t.type == :word }

          first_word = word_tokens.first&.value&.downcase&.to_sym
          return { menu_items: [], ghost: EMPTY_GHOST } unless first_word

          spec = Pito::Grammar::Registry.specs_for_alias(namespace: :chat, token: first_word)
          unless spec
            # Verb stage: the first word doesn't resolve to a chat verb yet —
            # ghost-complete it to the unique verb it prefixes (`sy` → `sync`).
            return { menu_items: [], ghost: free_verb_ghost(text, word_tokens) }
          end

          if spec.name == :list && (g = Pito::Suggestions::ListClauseGhost.ghost(text))
            return { menu_items: [], ghost: g }
          end

          if spec.name == :sync && (g = Pito::Suggestions::SyncClauseGhost.ghost(text))
            return { menu_items: [], ghost: g }
          end

          ghost = compute_ghost(text, spec, tokens, authenticated:)
          { menu_items: [], ghost: ghost }
        end

        # Verb-stage ghost for free (non-slash) input. When the user is still
        # typing the first word (single token, no trailing space) and it doesn't
        # resolve to a chat verb, complete it to the unique chat verb it prefixes.
        # Mirrors the slash verb-stage prefix match (`verb_stage_completions`),
        # expressed as ghost text instead of a palette. Stays silent when the
        # prefix is ambiguous (matches more than one verb).
        def free_verb_ghost(text, word_tokens)
          return EMPTY_GHOST if text.end_with?(" ")
          return EMPTY_GHOST unless word_tokens.size == 1

          partial = word_tokens.first.value.to_s.downcase
          return EMPTY_GHOST if partial.empty?

          names = Pito::Grammar::Registry.specs(namespace: :chat)
            .map { |spec| spec.name.to_s }
            .select { |name| name.start_with?(partial) && name != partial }
            .uniq

          return EMPTY_GHOST unless names.size == 1

          { complete_current: names.first[partial.length..], next_hint: "" }
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
          # `[0...-1]` (drop the current partial word) is safe when empty — a bare
          # complete verb like "list"/"ls" has zero typed_words, and `.first(-1)`
          # would raise "negative array size" (crashed the chat-verb suggestion).
          words_to_consume = ends_with_space ? typed_words : typed_words[0...-1]
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
            # At a fresh slot: for a static enum slot, ghost the FIRST value as a
            # real (TAB-completable) completion — not a `<bracketed>` placeholder
            # the user can't accept. Fall back to the slot-name hint only for
            # dynamic / valueless slots.
            completion = default_enum_completion(active_slot)
            if completion.empty?
              { complete_current: "", next_hint: next_hint_for_slot(active_slot) }
            else
              { complete_current: completion, next_hint: "" }
            end
          else
            # `--help` ghost: any partial starting with "-" that prefixes "--help".
            if current_partial.start_with?("-") && "--help".start_with?(current_partial.downcase)
              return { complete_current: "--help"[current_partial.length..], next_hint: "" }
            end

            # complete_current: if current partial uniquely prefixes one vocab member.
            completion = compute_current_completion(active_slot, current_partial, authenticated:)
            { complete_current: completion, next_hint: "" }
          end
        end

        # First canonical value of a static enum slot — used as the default
        # TAB-completable ghost when the cursor sits at a fresh slot. Returns ""
        # for dynamic slots (fetched separately) or non-enum/valueless slots.
        def default_enum_completion(slot)
          return "" unless slot&.source.is_a?(Symbol)

          vocab = Pito::Grammar::Registry.vocabulary(slot.source)
          return "" unless vocab && !vocab.dynamic? && vocab.canonical.any?

          vocab.canonical.first.to_s
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
