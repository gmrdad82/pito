# frozen_string_literal: true

module Pito
  module Dispatch
    # Pure Config-reader that derives the reply-availability matrix from tools.yml.
    #
    # Memoized off Config.data; call reload! (after Config.reload!) to invalidate.
    # Wired in config/initializers/pito_dispatch_config.rb so both caches clear
    # together on every to_prepare cycle in development.
    #
    # Public API:
    #   Matrix.targets                            # => Array<String> all reply_target ids
    #   Matrix.actions_for(target_id)             # => Array<String> canonical tokens +
    #                                             #    tool-level aliases + per-target aliases
    #                                             #    + universal reply tokens
    #   Matrix.mode_for(target_id, action: nil)   # => :append | :mutate | nil
    #   Matrix.tool_for(action)                   # => String (canonical) | nil
    #   Matrix.tool_enabled?(tool)                # => Boolean (live enabled_if: readiness)
    #   Matrix.available?(target_id, action)      # => Boolean (per-action enabled_if: readiness)
    #   Matrix.universal_tokens                   # => Array<String>
    #   Matrix.reload!                            # clears memoization
    #
    # `actions_for` (and everything gating DISPATCH — ToolDelegator,
    # Handler#declared?, #mode_for) stays UNFILTERED by a tool's `enabled_if:`
    # readiness on purpose: a typed reply must always reach the tool's own
    # honest error (e.g. Ai::Client::NotConfigured), never a generic
    # invalid_action. `tool_enabled?` / `available?` are the PRESENTATION-ONLY
    # twins — read by Pito::FollowUp::Registry#presentable_actions_for and
    # (for the chat palette) directly — so what's OFFERED can be narrower than
    # what's HONORED.
    module Matrix
      module_function

      # All reply_target ids declared across every tool's reply.targets in tools.yml.
      def targets
        idx[:targets]
      end

      # Every action token available on target_id: canonical tool names, tool-level
      # aliases, per-target aliases (e.g. new → [create] on resume_missing), and the
      # full universal reply set (share / revoke / unshare / help). Tokens are
      # deduplicated and in a stable order (tools first, universals last).
      # Returns [] for an unknown target.
      def actions_for(target_id)
        idx[:actions][target_id.to_s] || []
      end

      # All universal reply tokens: canonical names + aliases from universal_reply.
      # For the current tools.yml: share, revoke, unshare, help.
      def universal_tokens
        idx[:universal_tokens]
      end

      # Mode (:append or :mutate) for action on target_id; alias-aware.
      #
      # * action nil  → derived "base mode" for the target:
      #                 :mutate when ALL tool entries on the target are :mutate,
      #                 :append otherwise. Matches the DSL handler's class-level mode.
      # * universal   → always :append (regardless of target).
      # * known alias → resolves per-target alias first, then global tool alias.
      # * unknown     → the target's BASE mode (mirrors the old DSL's
      #                 mode_for_action fallback; controller routing depends on it).
      #
      # Returns nil when target_id is not in tools.yml.
      def mode_for(target_id, action: nil)
        t = target_id.to_s
        return nil unless idx[:targets].include?(t)

        if action.nil?
          idx[:base_mode][t]
        else
          a = action.to_s.downcase

          # A token the target itself declares (canonical tool or per-target
          # alias) always resolves to the tool's declared mode — tool config wins
          # over the universal set, so a universal token can never override a
          # tool's own declaration on its target.
          canonical = resolve_tool_for(t, a)
          declared  = canonical && idx.dig(:tool_modes, t, canonical)
          return declared if declared

          # Universal reply tools are :append, unless this target is in the tool's except: set.
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

      # Returns the canonical tool name for an action token by scanning tool-level
      # and universal_reply aliases. Does NOT resolve per-target aliases (those are
      # target-scoped; use mode_for for that resolution).
      # Returns nil for unknown tokens.
      def tool_for(action)
        idx[:tool_index][action.to_s.downcase]
      end

      # True when the CANONICAL tool +tool+ declares no `enabled_if:`
      # condition, or the condition it names currently holds — resolved LIVE
      # via Pito::Dispatch::Availability on every call (never memoized), so a
      # mid-conversation `/config ai` is honored on the very next read.
      # PRESENTATION-ONLY (see the class header) — an unknown tool name is
      # treated as enabled (nothing to gate).
      def tool_enabled?(tool)
        condition = idx[:tool_conditions][tool.to_s]
        condition.blank? || Pito::Dispatch::Availability.ready?(condition)
      end

      # The per-action twin of #tool_enabled? — resolves +action+ (a
      # canonical tool name, tool-level alias, or per-target alias) to its
      # canonical tool on +target_id+ first. PRESENTATION-ONLY (see the
      # class header); Pito::FollowUp::Registry#presentable_actions_for is
      # the one generic call site every presentation surface shares.
      def available?(target_id, action)
        canonical = resolve_tool_for(target_id.to_s, action.to_s.downcase) || action.to_s
        tool_enabled?(canonical)
      end

      # Clears memoization. Must be called after Config.reload! to keep the matrix
      # consistent with the freshly-loaded tools.yml document.
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
        tool_modes           = {}         # target_id => { canonical_tool => :symbol }
        tool_index           = {}         # token => canonical_tool (global, tool-level)
        per_target_alias_idx = {}         # target_id => { alias_token => canonical_tool }
        tool_conditions      = {}         # canonical_tool => enabled_if: condition name, or nil

        # Step 0 — each tool's declared `enabled_if:` condition name, if any —
        # collected regardless of which branches (chat/slash/reply) the tool
        # declares, since a tool's readiness is the same fact everywhere it's
        # offered. WHICH condition a tool names is static (safe to memoize);
        # whether that condition currently holds is resolved live by
        # #tool_enabled? / #available?, never here.
        (data[:tools] || {}).each do |vname, vbody|
          next unless vbody.is_a?(Hash) && vbody[:enabled_if]

          tool_conditions[vname.to_s] = vbody[:enabled_if].to_s
        end

        # Step 1 — global tool-level alias index (top-level tools + universal_reply).
        build_tool_alias_index(data, tool_index)

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

        # Step 3 — scan all tools' reply targets.
        (data[:tools] || {}).each do |vname, vbody|
          next unless vbody.is_a?(Hash) && vbody[:reply]

          canonical    = vname.to_s
          # Only the canonical tool name populates actions_for. Tool-level aliases
          # are chat-context synonyms (e.g. analyze→analytics/stats, list→ls) and
          # must NOT appear as reply-target action tokens — they would pollute the
          # suggestions palette with confusing entries. Aliases that are meaningful
          # in reply context (del/rm, pub, order) are declared as per-target aliases
          # on the specific reply.targets entries in tools.yml.
          tool_tokens  = [ canonical ]

          (vbody.dig(:reply, :targets) || {}).each do |target_sym, target_body|
            tid  = target_sym.to_s
            mode = target_body[:mode]&.to_sym || :append

            targets << tid unless targets.include?(tid)
            (tool_modes[tid] ||= {})[canonical] = mode

            # Per-target aliases (e.g. new → resume_missing with aliases: [create]).
            per_target_aliases = Array(target_body[:aliases]).map(&:to_s)
            per_target_aliases.each do |a|
              (per_target_alias_idx[tid] ||= {})[a] = canonical
            end

            (actions[tid] ||= []).concat(tool_tokens + per_target_aliases)
          end
        end

        # Step 4 — append universals to each target's action list + derive base modes.
        # Tokens whose except: set includes this target are skipped for that target.
        targets.each do |tid|
          specific      = actions[tid] || []
          injectable    = universal_tokens.reject { |tok| universal_excepts[tok]&.include?(tid) }
          actions[tid]  = specific.concat(injectable).uniq.freeze

          tmodes = (tool_modes[tid] || {}).values
          # :mutate iff every tool mode for this target is :mutate AND there is
          # at least one entry. Mixed or empty → :append.
          base_mode[tid] = (tmodes.any? && tmodes.all? { |m| m == :mutate }) ? :mutate : :append
        end

        {
          targets:               targets.freeze,
          actions:               actions.freeze,
          base_mode:             base_mode.freeze,
          tool_modes:            tool_modes.transform_values(&:freeze).freeze,
          tool_index:            tool_index.freeze,
          per_target_alias_idx:  per_target_alias_idx.transform_values(&:freeze).freeze,
          tool_conditions:       tool_conditions.freeze,
          universal_tokens:      universal_tokens,
          universal_modes:       universal_modes.freeze,
          universal_excepts:     universal_excepts.transform_values(&:freeze).freeze
        }.freeze
      end

      def build_tool_alias_index(data, tool_index)
        (data[:tools] || {}).each do |vname, vbody|
          canonical = vname.to_s
          tool_index[canonical] = canonical
          next unless vbody.is_a?(Hash)
          Array(vbody[:aliases]).each { |a| tool_index[a.to_s] = canonical }
        end

        (data[:universal_reply] || {}).each do |vname, vbody|
          canonical = vname.to_s
          tool_index[canonical] = canonical
          next unless vbody.is_a?(Hash)
          Array(vbody[:aliases]).each { |a| tool_index[a.to_s] = canonical }
        end
      end

      def resolve_tool_for(target_id, action_token)
        # Per-target aliases take precedence (e.g. "create" → "new" on resume_missing).
        per_target = idx.dig(:per_target_alias_idx, target_id, action_token)
        return per_target if per_target

        # Fall back to the global tool/alias index.
        idx[:tool_index][action_token]
      end
    end
  end
end
