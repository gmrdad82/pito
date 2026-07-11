# frozen_string_literal: true

module Pito
  module Dispatch
    # Pure Config-reader that derives the reply-availability matrix from verbs.yml.
    #
    # Memoized off Config.data; call reload! (after Config.reload!) to invalidate.
    # Wired in config/initializers/pito_dispatch_config.rb so both caches clear
    # together on every to_prepare cycle in development.
    #
    # Public API:
    #   Matrix.targets                            # => Array<String> all reply_target ids
    #   Matrix.actions_for(target_id)             # => Array<String> canonical tokens +
    #                                             #    verb-level aliases + per-target aliases
    #                                             #    + universal reply tokens
    #   Matrix.mode_for(target_id, action: nil)   # => :append | :mutate | nil
    #   Matrix.verb_for(action)                   # => String (canonical) | nil
    #   Matrix.universal_tokens                   # => Array<String>
    #   Matrix.reload!                            # clears memoization
    module Matrix
      module_function

      # All reply_target ids declared across every verb's reply.targets in verbs.yml.
      def targets
        idx[:targets]
      end

      # Every action token available on target_id: canonical verb names, verb-level
      # aliases, per-target aliases (e.g. new → [create] on resume_missing), and the
      # full universal reply set (share / revoke / unshare / help). Tokens are
      # deduplicated and in a stable order (verbs first, universals last).
      # Returns [] for an unknown target.
      def actions_for(target_id)
        idx[:actions][target_id.to_s] || []
      end

      # All universal reply tokens: canonical names + aliases from universal_reply.
      # For the current verbs.yml: share, revoke, unshare, help.
      def universal_tokens
        idx[:universal_tokens]
      end

      # Mode (:append or :mutate) for action on target_id; alias-aware.
      #
      # * action nil  → derived "base mode" for the target:
      #                 :mutate when ALL verb entries on the target are :mutate,
      #                 :append otherwise. Matches the DSL handler's class-level mode.
      # * universal   → always :append (regardless of target).
      # * known alias → resolves per-target alias first, then global verb alias.
      # * unknown     → the target's BASE mode (mirrors the old DSL's
      #                 mode_for_action fallback; controller routing depends on it).
      #
      # Returns nil when target_id is not in verbs.yml.
      def mode_for(target_id, action: nil)
        t = target_id.to_s
        return nil unless idx[:targets].include?(t)

        if action.nil?
          idx[:base_mode][t]
        else
          a = action.to_s.downcase

          # A token the target itself declares (canonical verb or per-target
          # alias) always resolves to the verb's declared mode — verb config wins
          # over the universal set, so a universal token can never override a
          # verb's own declaration on its target.
          canonical = resolve_verb_for(t, a)
          declared  = canonical && idx.dig(:verb_modes, t, canonical)
          return declared if declared

          # Universal reply verbs are :append, unless this target is in the verb's except: set.
          umode = idx[:universal_modes][a]
          if umode
            excepted = idx[:universal_excepts][a]
            return umode unless excepted&.include?(t)
          end

          # Unknown action → the target's BASE mode: the handler contract falls
          # back to the class-level mode for unrecognized tokens, and the
          # controller's route-by-mode depends on that (e.g. the `--help`
          # fall-through). Returning nil here would break that routing.
          idx[:base_mode][t]
        end
      end

      # Returns the canonical verb name for an action token by scanning verb-level
      # and universal_reply aliases. Does NOT resolve per-target aliases (those are
      # target-scoped; use mode_for for that resolution).
      # Returns nil for unknown tokens.
      def verb_for(action)
        idx[:verb_index][action.to_s.downcase]
      end

      # Clears memoization. Must be called after Config.reload! to keep the matrix
      # consistent with the freshly-loaded verbs.yml document.
      def reload!
        @idx = nil
      end

      # ── Private ────────────────────────────────────────────────────────────────

      def idx
        @idx ||= build_index
      end

      def build_index
        data = Pito::Dispatch::Config.data

        # Mutable accumulators (frozen at end).
        targets              = []         # Array<String> — all reply_target ids
        actions              = {}         # target_id => Array<String>
        base_mode            = {}         # target_id => :append | :mutate
        verb_modes           = {}         # target_id => { canonical_verb => :symbol }
        verb_index           = {}         # token => canonical_verb (global, verb-level)
        per_target_alias_idx = {}         # target_id => { alias_token => canonical_verb }

        # Step 1 — global verb-level alias index (top-level verbs + universal_reply).
        build_verb_alias_index(data, verb_index)

        # Step 2 — universal reply tokens and their modes.
        universal_tokens  = []
        universal_modes   = {}
        universal_excepts = {}   # token => Set<String> of excepted reply_target ids

        (data[:universal_reply] || {}).each do |vname, vbody|
          canonical = vname.to_s
          umode     = vbody[:mode]&.to_sym || :append
          uexcept   = Array(vbody[:except]).map(&:to_s).to_set

          universal_tokens << canonical
          universal_modes[canonical]   = umode
          universal_excepts[canonical] = uexcept

          Array(vbody[:aliases]).each do |a|
            tok = a.to_s
            universal_tokens << tok
            universal_modes[tok]   = umode
            universal_excepts[tok] = uexcept
          end
        end
        universal_tokens = universal_tokens.uniq.freeze

        # Step 3 — scan all verbs' reply targets.
        (data[:verbs] || {}).each do |vname, vbody|
          next unless vbody.is_a?(Hash) && vbody[:reply]

          canonical    = vname.to_s
          # Only the canonical verb name populates actions_for. Verb-level aliases
          # are chat-context synonyms (e.g. analyze→analytics/stats, list→ls) and
          # must NOT appear as reply-target action tokens — they would pollute the
          # suggestions palette with confusing entries. Aliases that are meaningful
          # in reply context (del/rm, pub, order) are declared as per-target aliases
          # on the specific reply.targets entries in verbs.yml.
          verb_tokens  = [ canonical ]

          (vbody.dig(:reply, :targets) || {}).each do |target_sym, target_body|
            tid  = target_sym.to_s
            mode = target_body[:mode]&.to_sym || :append

            targets << tid unless targets.include?(tid)
            (verb_modes[tid] ||= {})[canonical] = mode

            # Per-target aliases (e.g. new → resume_missing with aliases: [create]).
            per_target_aliases = Array(target_body[:aliases]).map(&:to_s)
            per_target_aliases.each do |a|
              (per_target_alias_idx[tid] ||= {})[a] = canonical
            end

            (actions[tid] ||= []).concat(verb_tokens + per_target_aliases)
          end
        end

        # Step 4 — append universals to each target's action list + derive base modes.
        # Tokens whose except: set includes this target are skipped for that target.
        targets.each do |tid|
          specific      = actions[tid] || []
          injectable    = universal_tokens.reject { |tok| universal_excepts[tok]&.include?(tid) }
          actions[tid]  = specific.concat(injectable).uniq.freeze

          tmodes = (verb_modes[tid] || {}).values
          # :mutate iff every verb mode for this target is :mutate AND there is
          # at least one entry. Mixed or empty → :append.
          base_mode[tid] = (tmodes.any? && tmodes.all? { |m| m == :mutate }) ? :mutate : :append
        end

        {
          targets:               targets.freeze,
          actions:               actions.freeze,
          base_mode:             base_mode.freeze,
          verb_modes:            verb_modes.transform_values(&:freeze).freeze,
          verb_index:            verb_index.freeze,
          per_target_alias_idx:  per_target_alias_idx.transform_values(&:freeze).freeze,
          universal_tokens:      universal_tokens,
          universal_modes:       universal_modes.freeze,
          universal_excepts:     universal_excepts.transform_values(&:freeze).freeze
        }.freeze
      end

      def build_verb_alias_index(data, verb_index)
        (data[:verbs] || {}).each do |vname, vbody|
          canonical = vname.to_s
          verb_index[canonical] = canonical
          next unless vbody.is_a?(Hash)
          Array(vbody[:aliases]).each { |a| verb_index[a.to_s] = canonical }
        end

        (data[:universal_reply] || {}).each do |vname, vbody|
          canonical = vname.to_s
          verb_index[canonical] = canonical
          next unless vbody.is_a?(Hash)
          Array(vbody[:aliases]).each { |a| verb_index[a.to_s] = canonical }
        end
      end

      def resolve_verb_for(target_id, action_token)
        # Per-target aliases take precedence (e.g. "create" → "new" on resume_missing).
        per_target = idx.dig(:per_target_alias_idx, target_id, action_token)
        return per_target if per_target

        # Fall back to the global verb/alias index.
        idx[:verb_index][action_token]
      end
    end
  end
end
