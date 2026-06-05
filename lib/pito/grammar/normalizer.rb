# frozen_string_literal: true

module Pito
  module Grammar
    # Normalizer: converts a raw token stream into a Match (or Array<Match>).
    #
    # call      — single-op normalization
    # call_ops  — splits on verb boundaries, returns Array<Match>
    class Normalizer
      # ── Public API ─────────────────────────────────────────────────────────

      # @param tokens [Array<Pito::Lex::Token>] full token stream from Lexer
      # @param namespace [Symbol] :chat | :hashtag | :slash
      # @param context  [Object, nil] passed through to dynamic vocabulary resolvers
      # @return [Pito::Grammar::Match]
      def self.call(tokens, namespace:, context: nil)
        new(namespace:, context:).normalize(tokens)
      end

      # Splits token stream on verb boundaries and normalises each segment.
      # @return [Array<Pito::Grammar::Match>]
      def self.call_ops(tokens, namespace:, context: nil)
        new(namespace:, context:).split_and_normalize(tokens)
      end

      # ── Internals ───────────────────────────────────────────────────────────

      private_class_method :new

      def initialize(namespace:, context:)
        @namespace = namespace
        @context   = context
      end

      # ── Single-op normalization ─────────────────────────────────────────────

      def normalize(tokens)
        content = meaningful_tokens(tokens)

        # Step 1: verb resolution — first :word token
        verb_tok = content.shift
        return no_match(content) unless verb_tok&.type == :word

        spec = Registry.specs_for_alias(namespace: @namespace, token: verb_tok.value.downcase.to_sym)
        return no_match([ verb_tok, *content ]) unless spec

        process(spec, content)
      end

      # ── Multi-op splitting ──────────────────────────────────────────────────

      def split_and_normalize(tokens)
        content = meaningful_tokens(tokens)
        return [ no_match([]) ] if content.empty?

        segments = split_into_segments(content)
        segments.map { |seg| normalize_segment(seg) }
      end

      private

      # ── Helpers: token filtering ────────────────────────────────────────────

      # Remove :eof and :comma; keep everything else.
      def meaningful_tokens(tokens)
        tokens.reject { |t| t.type == :eof || t.type == :comma }
      end

      # ── No-match result ─────────────────────────────────────────────────────

      def no_match(content_tokens)
        leftovers = content_tokens.select { |t| t.type == :word }.map(&:value)
        Match.new(namespace: @namespace, name: nil, leftovers:, matched: false, confidence: 0.0)
      end

      # ── Segment splitting for call_ops ──────────────────────────────────────

      # Splits content tokens (already meaningful) into segments, each starting
      # with a verb token.  The very first token is always the verb of segment 0.
      def split_into_segments(content)
        return [ content ] if content.empty?

        segments     = []
        current_seg  = []

        content.each_with_index do |tok, idx|
          if idx == 0
            # First token always starts segment 0
            current_seg << tok
          elsif tok.type == :word &&
                Registry.specs_for_alias(namespace: @namespace, token: tok.value.downcase.to_sym)
            # This word resolves as a verb — start a new segment.
            # Drop a trailing `and` / connective from previous segment.
            current_seg.pop if trailing_connective?(current_seg.last)
            segments << current_seg
            current_seg = [ tok ]
          else
            current_seg << tok
          end
        end

        segments << current_seg unless current_seg.empty?
        segments
      end

      def trailing_connective?(tok)
        return false unless tok&.type == :word
        vocab = Registry.vocabulary(:connectives)
        vocab&.resolve(tok.value.downcase) ? true : false
      end

      # Normalize a pre-split segment (first token must be the verb).
      def normalize_segment(seg)
        # Clone so we can shift safely
        toks = seg.dup
        verb_tok = toks.shift
        return no_match([]) unless verb_tok&.type == :word

        spec = Registry.specs_for_alias(namespace: @namespace, token: verb_tok.value.downcase.to_sym)
        return no_match([ verb_tok, *toks ]) unless spec

        process(spec, toks)
      end

      # ── Core slot walk ──────────────────────────────────────────────────────

      def process(spec, content_tokens)
        values             = {}
        kwargs             = {}
        leftovers          = []
        unknowns           = []
        free_parts         = []   # ordered unconsumed tokens for :free slot
        pending_introducer = nil

        enum_slots    = spec.slots.select { |s| s.kind == :enum }
        literal_slots = spec.slots.select { |s| s.kind == :literal }
        free_slot     = spec.slots.find   { |s| s.kind == :free }

        # Mutable index; kv parsing consumes multiple tokens at once
        idx = 0
        while idx < content_tokens.length
          tok = content_tokens[idx]

          # ── @handle: merge :at + next :word into one string token ──────────
          if tok.type == :at && content_tokens[idx + 1]&.type == :word
            handle_val = "@#{content_tokens[idx + 1].value}"
            tok = Pito::Lex::Token.new(type: :word, value: handle_val, position: tok.position)
            idx += 2
            # fall through with merged token
          else
            idx += 1
          end

          # ── kv detection: word followed by :colon or :equals ───────────────
          if tok.type == :word
            next_tok = content_tokens[idx]  # idx already advanced past current
            if next_tok && (next_tok.type == :colon || next_tok.type == :equals)
              key = tok.value.to_sym
              idx += 1 # skip colon/equals
              value_str, consumed = read_kv_value(content_tokens, idx)
              idx += consumed
              kwargs[key] = coerce_numeric(value_str)
              next
            end
          end

          # ── connective handling ─────────────────────────────────────────────
          if tok.type == :word
            connectives_vocab = Registry.vocabulary(:connectives)
            if connectives_vocab&.resolve(tok.value.downcase)
              word = tok.value.downcase
              pending_introducer = :for if word == "for"
              # `and` is a soft separator — no state change, just skip
              next
            end
          end

          # ── filler stripping ────────────────────────────────────────────────
          if tok.type == :word || tok.type == :number || tok.type == :string
            raw_val = tok.value
            global_filler       = Registry.vocabulary(:fillers)&.filler?(raw_val)
            active_enum_filler  = enum_slots.any? do |sl|
              next false unless sl.source.is_a?(Symbol)
              Registry.vocabulary(sl.source)&.filler?(raw_val)
            end
            next if global_filler || active_enum_filler
          end

          # ── literal slot resolution ─────────────────────────────────────────
          if tok.type == :word || tok.type == :number || tok.type == :string
            raw_val = tok.value
            lit_slot = resolve_literal(raw_val, literal_slots, values)
            if lit_slot
              values[lit_slot.name] = raw_val.downcase
              next
            end
          end

          # ── enum resolution ─────────────────────────────────────────────────
          if tok.type == :word || tok.type == :number || tok.type == :string
            raw_val = tok.value
            resolved_slot, canonical = resolve_enum(raw_val, enum_slots, values, pending_introducer)

            if resolved_slot
              pending_introducer = nil if resolved_slot.introducer
              if resolved_slot.repeatable?
                values[resolved_slot.name] ||= []
                values[resolved_slot.name] << canonical
              else
                values[resolved_slot.name] = canonical
              end
              next
            end

            # Could not resolve to any enum slot
            if free_slot
              free_parts << raw_val
            elsif enum_slots.any?
              unknowns << raw_val
            else
              leftovers << raw_val
            end
            next
          end

          # ── other tokens (punctuation etc.) ────────────────────────────────
          if free_slot
            free_parts << tok.value
          else
            leftovers << tok.value
          end
        end

        # ── materialise free slot ───────────────────────────────────────────
        values[free_slot.name] = free_parts.join(" ") if free_slot && !free_parts.empty?

        # ── confidence ─────────────────────────────────────────────────────
        noise      = unknowns.length + leftovers.length
        confidence = noise == 0 ? 1.0 : [ 1.0 - (0.2 * noise), 0.1 ].max

        Match.new(
          namespace:  @namespace,
          name:       spec.name,
          values:,
          kwargs:,
          leftovers:,
          unknowns:,
          confidence:,
          matched:    true
        )
      end

      # ── Enum resolution helper ───────────────────────────────────────────────

      # Returns [slot, canonical_value] or [nil, nil].
      # Respects: introducer gating, already-filled non-repeatable slots, and
      # conditional eligibility (slot.eligible?(values)).
      def resolve_enum(raw_val, enum_slots, values, pending_introducer)
        downcased = raw_val.to_s.downcase

        # If there's a pending introducer, try introducer-gated slots first
        if pending_introducer
          gated_slots = enum_slots.select { |s| s.introducer == pending_introducer }
          gated_slots.each do |sl|
            next unless sl.eligible?(values)
            next if slot_filled_non_repeatable?(sl, values)
            next unless sl.source.is_a?(Symbol)
            canon = Registry.vocabulary(sl.source)&.resolve(downcased)
            return [ sl, canon ] if canon
          end
        end

        # Then try un-gated (no introducer) slots in order
        enum_slots.each do |sl|
          next if sl.introducer && sl.introducer != pending_introducer
          next unless sl.eligible?(values)
          next if slot_filled_non_repeatable?(sl, values)
          next unless sl.source.is_a?(Symbol)
          canon = Registry.vocabulary(sl.source)&.resolve(downcased)
          return [ sl, canon ] if canon
        end

        [ nil, nil ]
      end

      def slot_filled_non_repeatable?(slot, values)
        !slot.repeatable? && values.key?(slot.name)
      end

      # ── Literal slot resolution helper ───────────────────────────────────────

      # Returns the first unfilled literal slot whose vocabulary resolves raw_val,
      # or nil if none. Used to track literal values in the `values` hash so that
      # conditional (when:) enum/kv slots can check eligibility.
      def resolve_literal(raw_val, literal_slots, values)
        downcased = raw_val.to_s.downcase
        literal_slots.each do |sl|
          next if values.key?(sl.name)  # already filled
          next unless sl.source.is_a?(Symbol)
          vocab = Registry.vocabulary(sl.source)
          next unless vocab
          resolved = vocab.resolve(downcased) || (vocab.canonical.include?(raw_val) ? raw_val : nil)
          return sl if resolved
        end
        nil
      end

      # ── KV value reader ──────────────────────────────────────────────────────

      # Reads value tokens starting at idx; returns [joined_string, count_consumed].
      # Stops at another kv boundary or end of tokens.
      def read_kv_value(tokens, idx)
        parts     = []
        consumed  = 0

        while idx < tokens.length
          tok = tokens[idx]
          break if tok.type == :eof
          # Stop if we hit a new kv boundary (word followed by colon/equals)
          if tok.type == :word && tokens[idx + 1]&.type&.in?([ :colon, :equals ])
            break
          end
          # Stop at connectives that aren't part of a value
          parts << tok.value.to_s
          consumed += 1
          idx += 1
        end

        [ parts.join, consumed ]
      end

      # ── Numeric coercion ─────────────────────────────────────────────────────

      def coerce_numeric(str)
        return str.to_i if str.match?(/\A\d+\z/)
        return str.to_f if str.match?(/\A\d+\.\d+\z/)
        str
      end
    end
  end
end
