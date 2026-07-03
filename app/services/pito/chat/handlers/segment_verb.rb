# frozen_string_literal: true

# The ONE generic handler behind every "segment verb" (plan-0.9.5 D20/D21).
#
# A segment verb promotes a single :enhanced segment of `show`/`analyze` into its
# own top-level chat verb — `at-a-glance game #5`, `similar game #5`, `videos
# channel @h`, `breakdowns vid #7`, … — additive, with show/analyze untouched.
# Semantics are exactly `<parent> <noun> <ref> only <segment>`: the SAME entity
# resolution, the SAME emission path, the SAME not-found / rejection copy, and the
# SAME follow-up wiring as the parent verb's `only <segment>` form.
#
# ## How one class serves all seven verbs
#
# The concrete verb is read from `message.verb` (canonicalised by the parser, so
# aliases like `glance`/`similars`/`vids` all arrive as their canonical verb).
# Its (parent, segment) mapping lives in CONFIG — `verbs.<verb>.chat.segment_of`
# — never in Ruby. This handler resolves that pair, then drives the parent
# handler through its `drive_segment` seam, which runs the parent's normal
# `call` with the segment selection forced to `only <segment>`. Because the
# parent does the resolving and emitting, behaviour is byte-identical to the
# typed `only <segment>` form (the recognition/handler matrices prove it).
#
# ## Entity availability
#
# A segment verb only accepts entities whose parent segment table contains that
# segment (e.g. `videos` → channel only). This is NOT enforced here: the parent's
# forced selection validates the segment against the resolved entity's table, so
# `similar channel @x` yields the exact `segments.unknown` rejection that
# `show channel @x only similar` already produces. One code path, one copy.
#
# No `self.verb` / `self.description_key` — those are per-verb and derive from
# config; nothing reads them for a config-dispatched multi-verb handler.
module Pito
  module Chat
    module Handlers
      class SegmentVerb < Pito::Chat::Handler
        def call
          binding = segment_binding
          return binding if binding.is_a?(Pito::Chat::Result::Error)

          parent_verb, segment, entity = binding
          opts = entity ? { entity: } : {}
          parent_handler(parent_verb).new(
            message:, conversation:, channel:, period:,
            follow_up:, viewport_width:, kwargs:
          ).drive_segment(segment, **opts)
        end

        private

        # The (parent_verb, segment, forced_entity) this verb drives — or a
        # rejection Result when the keyed form is missing its noun. Two config
        # shapes (plan-0.9.5 D20 + E14):
        #
        #   FLAT   `segment_of: { verb:, segment: }` — entity nil; the typed noun
        #          routes the entity in the parent (the W7 segment verbs).
        #   KEYED  `segment_of: { <noun>: { verb:, segment:, entity: }, … }` — the
        #          `linked` forms: the noun names the segment and `entity:` FORCES
        #          the parent's branch (`linked game #7` → show vid #7 only
        #          linked-game; `linked vids #3` → show game #3 only linked-videos).
        def segment_binding
          cfg = Pito::Dispatch::Config.verb(message.verb).dig(:chat, :segment_of)
          return [ cfg.fetch(:verb).to_s, cfg.fetch(:segment).to_s, nil ] if flat_binding?(cfg)

          branch = keyed_branch(cfg)
          return no_noun_rejection unless branch

          [ branch.fetch(:verb).to_s, branch.fetch(:segment).to_s, branch.fetch(:entity).to_s.to_sym ]
        end

        # Flat when the block itself carries the pair; keyed when its keys are nouns.
        def flat_binding?(cfg)
          cfg.key?(:verb) || cfg.key?(:segment)
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
        # Result::Error + `pito.chat.<verb>.needs_noun` idiom as the parents'
        # needs_ref), listing both forms.
        def no_noun_rejection
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.#{message.verb}.needs_noun",
            message_args: {}
          )
        end

        # Resolves the parent handler CLASS from the parent verb's own config
        # `chat.dispatch` declaration — no verb→class conditional in Ruby (D7),
        # and a future segment-bearing parent needs zero edits here.
        def parent_handler(parent_verb)
          Pito::Dispatch::Config.verb(parent_verb.to_sym)
                                .dig(:chat, :dispatch)
                                .then { |klass| Object.const_get("Pito::#{klass}") }
        end
      end
    end
  end
end
