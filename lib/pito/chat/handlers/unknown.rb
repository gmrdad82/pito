# frozen_string_literal: true

# Fallback handler for chat input pito can't parse at all (no recognised tool,
# not a greeting/farewell) — e.g. "boo!", "I'm hungry".
#
# This is NOT an error: a from-the-start-unintelligible message gets a witty,
# slightly ironic `:system` reply from the `pito.copy.huh` dictionary, always
# nudging toward `help`. Errors are reserved for input pito DID understand but
# couldn't act on (a known tool with broken args/kwargs) — those come from the
# tool handlers themselves.
#
# Does NOT register a tool — invoked directly by the dispatcher's `:unknown`
# branch after all other dispatch paths are exhausted, and (since 3.0.1 P7) by
# Pito::Dispatch::Router#route_verb's soft-fail fallback: a handler that
# recognised its verb but couldn't act on a free-text-looking body returns the
# `nl_fallback: true` error marker, and the Router re-invokes this handler with
# the ORIGINAL raw utterance so the gate below runs as if the verb had never
# been captured. Both entries run the identical gate; the policy is unchanged.
#
# ── NL gate (3.0.0, locked policy — 2026-07-15) ──────────────────────────────
#
# Before falling back to the witty `huh` reply, free text gets ONE shot at the
# NL gate: router → (gated) mapper → auto-run / did-you-mean / unknown copy.
#
#   1. Pito::Nl::Router.route(utterance) < `suggest` (or nil — no `nl:`
#      block, sidecar down) → the `huh` copy below, UNCHANGED. The mapper is
#      NEVER consulted below `suggest` — out-of-domain input ("what's the
#      weather like") dies here; live-proof showed the mapper willingly
#      confabulates a command for anything it's asked to rewrite.
#   2. Router >= `suggest` → consult Pito::Nl::Mapper.map(utterance). Mapper
#      nil (sidecar down, or the completion didn't parse) → `huh` copy.
#   3. MISMATCH RE-TRY: when the mapped tool disagrees with the router's tool,
#      ONE re-try: Pito::Nl::Mapper.map(utterance, tool: route[:tool]) —
#      constrained to a single-tool grammar (Pito::Nl::GbnfBuilder's `only:`)
#      so the model has no legal completion FOR ANY TOOL BUT the router's.
#      Success (the retried mapping necessarily resolves to that SAME tool —
#      Mapper's own `tool:` contract) REPLACES the original mapping for
#      everything below: the tools now legitimately agree, so auto_run (step
#      5) is back on the table. Failure (nil — the model genuinely can't
#      place the utterance under that tool) falls back to the ORIGINAL
#      (unconstrained, mismatched) mapping, and step 5 is guaranteed to land
#      on did_you_mean since the tools still disagree.
#
#      WHY (live finding, 2026-07-15): "what rpgs do I have" routed to :list
#      at 0.966 confidence, but the UNCONSTRAINED mapper composed "rm games"
#      — a :delete command. The gate correctly refused to auto-run a
#      mismatch, but the did-you-mean it fell back to then suggested
#      `delete games`: the wrong-intent, destructive command, for a plain
#      read. Re-constraining the SAME utterance to tool-list's own grammar
#      fixes the SUGGESTION quality, not just the refusal.
#   4. CANONICALIZE: the mapper hands back its own raw completion text (which
#      may lead with an alias, e.g. "ls"); #canonicalize re-serializes ONLY the
#      leading verb token to the parsed canonical tool name (cheap — the parse
#      that validated the command already resolved it) so the SAME string is
#      both displayed and executed everywhere below.
#   5. Router >= `auto_run` AND the mapped tool is read-only (its tool-level
#      `read_only:` declaration in tools.yml — falling back to `mcp.read_only`
#      when the tool doesn't declare one; see #read_only?, 3.0.1 P13) AND the
#      mapped tool == the router's tool → execute the
#      canonical command directly through Pito::Dispatch::Router (the real
#      dispatch path — same one FollowUp::ToolDelegator and the AI orchestrator
#      re-enter commands through), prefixing the reply with an attribution
#      line (`pito.copy.nl.ran`).
#   6. Otherwise (suggest <= confidence < auto_run, OR a write-capable tool, OR
#      a router/mapper tool mismatch the re-try in step 3 couldn't resolve) →
#      emit a `did_you_mean` confirmation event (existing confirmation
#      semantics: `#<handle> confirm` re-enters the real dispatch path via
#      Pito::Confirmation::Executor#confirm_nl_run; `cancel`/decline discards,
#      same as any other confirmation).
#   7. Any sidecar down at any step degrades to the `huh` copy (K2 — never an
#      error surface) — steps 1/2/3 above already fold that in via
#      Router/Mapper's own forgiving nil contracts.
#
# ── Loop guard (3.0.1 P7 addendum — the policy above is unchanged) ───────────
#
# Step 5's re-entry passes `nl_retry: true`, so a mapped command that ITSELF
# soft-fails (its handler returns the `nl_fallback` marker) comes back here
# instead of re-entering the gate inside the nested dispatch — #run_now
# degrades it to the step-6 did-you-mean copy, never a recursive gate pass.
# Pito::Confirmation::Executor#confirm_nl_run (step 6's confirm) passes the
# same flag and renders the returned marker's own crisp error text.
module Pito
  module Chat
    module Handlers
      class Unknown < Pito::Chat::Handler
        # No self.tool — not registered against any tool.
        # Invoked directly by the dispatcher's :unknown branch.

        def call
          gated_result || huh_result
        end

        private

        # ── The gate ──────────────────────────────────────────────────────────

        def gated_result
          utterance = message.raw.to_s
          route = Pito::Nl::Router.route(utterance)
          return nil if route.nil? # < suggest (or NL routing off, or sidecar down) — mapper never consulted.

          mapped = Pito::Nl::Mapper.map(utterance)
          return nil if mapped.nil? # sidecar down, or the completion didn't parse to a known tool.

          mapped = retry_constrained(utterance, route) || mapped if route[:tool] != mapped[:tool]

          command = canonicalize(mapped[:command], mapped[:tool])

          if auto_run?(route: route, tool: mapped[:tool])
            run_now(command)
          else
            did_you_mean(command)
          end
        end

        # See "MISMATCH RE-TRY" (step 3) in the file header comment for the
        # WHY. Re-runs the mapper constrained to the router's own tool via a
        # single-tool grammar; a successful retry always resolves to that
        # SAME tool (Pito::Nl::Mapper#map's own `tool:` contract), so the
        # caller's subsequent `route[:tool] == mapped[:tool]` check in
        # #auto_run? passes on tool agreement alone — nil here (not just a
        # different tool) is the only possible failure, and the caller falls
        # back to the original, still-mismatched mapping in that case.
        def retry_constrained(utterance, route)
          Pito::Nl::Mapper.map(utterance, tool: route[:tool])
        end

        # Re-serializes only the leading token (the verb the mapper may have
        # spelled as an alias, e.g. "ls") to the canonical tool name the parse
        # already resolved — cheap, and it's what guarantees the displayed
        # command is byte-identical to what actually executes.
        def canonicalize(command, tool)
          command.to_s.sub(/\A\S+/, tool.to_s)
        end

        # auto_run requires ALL THREE: high confidence, a read-only tool (never
        # auto-run a write), and router/mapper agreement on which tool this is.
        def auto_run?(route:, tool:)
          return false unless route[:tool] == tool

          threshold = Pito::Dispatch::Config.nl_thresholds[:auto_run]
          return false if threshold.nil? || route[:confidence] < threshold

          read_only?(tool)
        end

        # Read-only in the AUTO-RUN sense: executing the tool mutates no owner
        # data. The tool-level `read_only:` declaration (tools.yml, 3.0.1 P13)
        # is authoritative when present — an explicit `false` wins over any mcp
        # flag. Absent, fall back to `mcp.read_only`: a tool exposed to MCP as
        # strictly side-effect-free is trivially safe to auto-run too. (The two
        # keys answer different questions — the analytics four warm caches /
        # call the YouTube API, so they are `mcp.read_only: false` for the
        # client readOnlyHint yet `read_only: true` here.) The schema-integrity
        # suite pins the exact effective set this predicate yields.
        def read_only?(tool)
          config = Pito::Dispatch::Config.tool(tool)
          return config[:read_only] == true if config.key?(:read_only)

          config.dig(:mcp, :read_only) == true
        rescue KeyError
          false
        end

        # ── auto-run ──────────────────────────────────────────────────────────

        # Re-enters the SAME uniform dispatch path a typed command runs
        # through (mirrors Pito::FollowUp::ToolDelegator / the AI orchestrator's
        # `render_command` — never a bespoke re-implementation of dispatch).
        # `nl_retry: true` is the loop guard (see the header addendum): a mapped
        # command that itself soft-fails returns its marker here and degrades to
        # the did-you-mean copy — the gate never recurses.
        def run_now(command)
          result = Pito::Dispatch::Router.call(
            input: command, conversation: conversation, channel: channel,
            period: period, viewport_width: viewport_width, nl_retry: true
          )
          return did_you_mean(command) if soft_failed?(result)
          return result unless result.is_a?(Pito::Chat::Result::Ok)

          attribution = { kind: :system, payload: { text: Pito::Copy.render("pito.copy.nl.ran", command: command) } }
          Pito::Chat::Result::Ok.new(events: [ attribution ] + result.events)
        end

        # The nested dispatch's "verb recognized, body not actionable" marker
        # (Pito::Chat::Result::Error#nl_fallback), returned un-fallen-back
        # because run_now dispatches with `nl_retry: true`.
        def soft_failed?(result)
          result.is_a?(Pito::Chat::Result::Error) && result.nl_fallback
        end

        # ── did-you-mean ──────────────────────────────────────────────────────

        # Existing confirmation semantics: target "confirmation" so `#<handle>
        # confirm`/`cancel` (+ aliases) already work unchanged. `nl_command` +
        # `conversation_id` ride the payload so Pito::Confirmation::Executor's
        # `confirm_nl_run` branch can re-enter the real dispatch path with no
        # signature change to the Executor's `confirm(command, payload)` contract.
        def did_you_mean(command)
          payload = {
            "command"         => "nl_run",
            "body"            => Pito::Copy.render("pito.copy.nl.did_you_mean", command: command),
            "html"            => false,
            "nl_command"      => command,
            "conversation_id" => conversation.id
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation: conversation)
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── unchanged fallback ────────────────────────────────────────────────

        def huh_result
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { text: Pito::Copy.render("pito.copy.huh") } }
          ])
        end
      end
    end
  end
end
