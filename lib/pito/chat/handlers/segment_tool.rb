# frozen_string_literal: true

# The ONE generic handler behind every "segment tool".
#
# A segment tool promotes a single :enhanced segment of `show`/`analyze` into its
# own top-level chat tool — `at-a-glance game #5`, `similar game #5`, `videos
# channel @h`, `breakdowns vid #7`, … — additive, with show/analyze untouched.
# Semantics are exactly `<parent> <noun> <ref> only <segment>`: the SAME entity
# resolution, the SAME emission path, the SAME not-found / rejection copy, and the
# SAME follow-up wiring as the parent tool's `only <segment>` form.
#
# ## How one class serves all seven tools
#
# The concrete tool is read from `message.tool` (canonicalised by the parser, so
# aliases like `glance`/`similars`/`vids` all arrive as their canonical tool).
# Its (parent, segment) mapping lives in CONFIG — `tools.<tool>.chat.segment_of`
# — never in Ruby. This handler resolves that pair, then drives the parent
# handler through its `drive_segment` seam, which runs the parent's normal
# `call` with the segment selection forced to `only <segment>`. Because the
# parent does the resolving and emitting, behaviour is byte-identical to the
# typed `only <segment>` form (the recognition/handler matrices prove it).
#
# ## Entity availability
#
# A segment tool only accepts entities whose parent segment table contains that
# segment (e.g. `videos` → channel only). This is NOT enforced here: the parent's
# forced selection validates the segment against the resolved entity's table, so
# `similar channel @x` yields the exact `segments.unknown` rejection that
# `show channel @x only similar` already produces. One code path, one copy.
#
# No `self.tool` / `self.description_key` — those are per-tool and derive from
# config; nothing reads them for a config-dispatched multi-tool handler.
module Pito
  module Chat
    module Handlers
      class SegmentTool < Pito::Chat::Handler
        def call
          binding = segment_binding
          return binding if binding.is_a?(Pito::Chat::Result::Error)

          parent_tool, segment, entity = binding
          opts = entity ? { entity: } : {}
          parent_handler(parent_tool).new(
            message:, conversation:, channel:, period:,
            follow_up:, viewport_width:, kwargs:
          ).drive_segment(segment, **opts)
        end

        private

        # The (parent_tool, segment, forced_entity) this tool drives — or a
        # rejection Result when the keyed form is missing its noun. Two config
        # shapes:
        #
        #   FLAT   `segment_of: { tool:, segment: }` — entity nil; the typed noun
        #          routes the entity in the parent.
        #   KEYED  `segment_of: { <noun>: { tool:, segment:, entity: }, … }` — the
        #          `linked` forms: the noun names the segment and `entity:` FORCES
        #          the parent's branch (`linked game #7` → show vid #7 only
        #          linked-game; `linked vids #3` → show game #3 only linked-videos).
        def segment_binding
          cfg = Pito::Dispatch::Config.tool(message.tool).dig(:chat, :segment_of)
          return [ cfg.fetch(:tool).to_s, cfg.fetch(:segment).to_s, nil ] if flat_binding?(cfg)

          branch = keyed_branch(cfg)
          return no_noun_rejection unless branch

          [ branch.fetch(:tool).to_s, branch.fetch(:segment).to_s, branch.fetch(:entity).to_s.to_sym ]
        end

        # Flat when the block itself carries the pair; keyed when its keys are nouns.
        def flat_binding?(cfg)
          cfg.key?(:tool) || cfg.key?(:segment)
        end

        # The keyed branch whose accepted noun (its key + `aliases:`) appears among
        # the message body tokens — `linked game …` → the game branch; `linked
        # videos …` → the vids branch via its alias. nil when no noun is present.
        def keyed_branch(cfg)
          body = message.body_tokens.map { |t| t.value.to_s.downcase }
          cfg.each do |noun, branch|
            accepted = [ noun.to_s ] + Array(branch[:aliases]).map(&:to_s)
            return branch if (accepted & body).any?
          end
          nil
        end

        # `linked #5` — no noun to name which linked view. Honest usage hint (same
        # Result::Error + `pito.chat.<tool>.needs_noun` idiom as the parents'
        # needs_ref), listing both forms.
        #
        # NL soft-fail (3.0.1 wave 2): when the noun-less body reads like free
        # text instead ("linked stuff about bosses" — verb captured, nothing
        # actionable), flag the error as an nl_fallback marker so
        # Pito::Dispatch::Router re-runs the ORIGINAL utterance through the NL
        # gate. nl_free_text_body? keeps the crisp usage hint for bare
        # `linked` and id-only bodies (`linked #5`), and for follow-up /
        # nl_eligible: false dispatches (machine-reconstructed input). The
        # marker still carries the needs_noun copy for any consumer that
        # renders it un-fallen-back (nl_retry loop guard, MCP projection).
        def no_noun_rejection
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.#{message.tool}.needs_noun",
            message_args: {},
            nl_fallback:  nl_free_text_body?
          )
        end

        # Resolves the parent handler CLASS from the parent tool's own config
        # `chat.dispatch` declaration — no tool→class conditional in Ruby,
        # and a future segment-bearing parent needs zero edits here.
        def parent_handler(parent_tool)
          Pito::Dispatch::Config.tool(parent_tool.to_sym)
                                .dig(:chat, :dispatch)
                                .then { |klass| Object.const_get("Pito::#{klass}") }
        end
      end
    end
  end
end
