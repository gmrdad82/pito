# frozen_string_literal: true

module Pito
  module Chat
    # Context-aware target resolution shared by verb handlers.
    #
    # A verb like `show`/`delete`/`reindex` acts on one game or video. It can be
    # reached three ways; `resolve_target` returns the SAME kind of record for all
    # three so the verb body stays identical:
    #
    #   * free-chat (`show game 5`)        → the TYPED ref (id `#N`/`N` or title),
    #                                        parsed from `message.raw`.
    #   * detail reply (`#<h> rm`)         → the source card's entity, read from its
    #                                        `<id_key>` payload field. No ref typed.
    #   * list reply (`#<h> show 5`)       → the typed ref, resolved AMONG the
    #                                        source list's rows (id/title), so a row
    #                                        that isn't in THAT list doesn't match.
    #
    # Mixed into `Pito::Chat::Handler`, so every verb handler has it. Callers pass
    # the model class, the detail payload id key, and the noun filler words:
    #
    #   resolve_target(::Game, id_key: :game_id, noun_fillers: %w[game games])
    #
    # Per-verb opt-in: call `id_only_resolution!` in a handler subclass to restrict
    # `find_by_ref` to numeric ids only (strips a leading `#`, then requires digits).
    # Title (ILIKE) lookup is skipped entirely. Default is id-and-title.
    #
    #   class Delete < Pito::Chat::Handler
    #     id_only_resolution!
    #   end
    #
    # @return the record, or nil (not found / not in the list's scope), or
    #   :needs_ref when free-chat / a list reply supplied no reference at all.
    module TargetResolution
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Restrict this handler to id-only resolution (no ILIKE title lookup).
        def id_only_resolution!
          @id_only_resolution = true
        end

        def id_only_resolution?
          @id_only_resolution || false
        end
      end

      def resolve_target(entity_class, id_key:, noun_fillers:)
        return resolve_free_chat(entity_class, noun_fillers) unless follow_up?

        payload = follow_up.source_event.payload.with_indifferent_access
        if payload[id_key].present?
          entity_class.find_by(id: payload[id_key])              # detail context
        else
          resolve_in_list(entity_class, payload, noun_fillers)   # list context
        end
      end

      # The source event's `reply_target` (follow-up replies only; nil in free chat).
      def reply_target
        return nil unless follow_up?

        follow_up.source_event.payload.to_h.with_indifferent_access[:reply_target].to_s.presence
      end

      # True when a verb that handles BOTH game + video should take the video
      # branch. In a follow-up reply the entity type is fixed by the source event's
      # `reply_target` (video_list / video_detail) — the reconstructed `<verb>
      # <rest>` carries no noun. In free chat it's the noun word the user typed.
      def video_target?(video_noun_fillers)
        return reply_target.to_s.start_with?("video") if follow_up?

        message.body_tokens.any? { |t| video_noun_fillers.include?(t.value.to_s.downcase) }
      end

      # The display reference for user-facing messages (e.g. not-found copy),
      # mirroring the three modes `resolve_target` uses: the typed ref (free-chat
      # or list reply), or the source card's entity id (detail reply).
      def target_ref(noun_fillers, id_key:)
        return extract_ref_from(resolution_raw, noun_fillers) unless follow_up?

        payload = follow_up.source_event.payload.to_h.with_indifferent_access
        return payload[id_key].to_s if payload[id_key].present?

        strip_noun(resolution_rest, noun_fillers)
      end

      # The raw text reference extraction reads. Verbs whose grammar appends
      # trailing clauses AFTER the reference (segment selection on `show`:
      # `show game 5 full` — plan-0.9.5 D3) override these to return the input
      # with those clauses stripped, so `find_by_ref` sees only the ref.
      def resolution_raw
        message.raw
      end

      # Reply-mode sibling of +resolution_raw+ (the `<verb> <rest>` reply text).
      def resolution_rest
        follow_up.rest
      end

      private

      def resolve_free_chat(entity_class, noun_fillers)
        ref = extract_ref_from(resolution_raw, noun_fillers)
        return :needs_ref if ref.blank?

        find_by_ref(entity_class, ref)
      end

      def resolve_in_list(entity_class, payload, noun_fillers)
        ref = strip_noun(resolution_rest, noun_fillers)
        return :needs_ref if ref.blank?

        record = find_by_ref(entity_class, ref)
        return nil if record.nil?

        ids = list_row_ids(payload)
        ids.empty? || ids.include?(record.id) ? record : nil
      end

      # ID form (`#5`/`5`/`# 5`) → by id; otherwise case-insensitive title.
      # The lexer splits `#9` into `#` + `9`, so strip a leading `#` + whitespace.
      # When the handler has opted into id-only resolution, non-numeric refs
      # return nil immediately — no ILIKE title lookup is performed.
      def find_by_ref(entity_class, ref)
        id = ref.sub(/\A#\s*/, "")
        return entity_class.find_by(id: id) if id.match?(/\A\d+\z/)
        return nil if self.class.id_only_resolution?

        entity_class.find_by("title ILIKE ?", ref)
      end

      # The game/video ids shown in a kv-table list: the first cell of each row is
      # `#<id>` (or the legacy `key: "#<id>"` shape).
      def list_row_ids(payload)
        Array(payload[:table_rows]).filter_map do |row|
          text = if row[:cells]
                   Array(row[:cells]).first&.dig(:text)
          else
                   row[:key] # legacy { key:, value: } row
          end
          next if text.blank?

          digits = text.to_s.sub(/\A#\s*/, "")
          digits.to_i if digits.match?(/\A\d+\z/)
        end
      end

      # Drop the verb word, then a leading noun filler — from raw chat input.
      def extract_ref_from(raw, noun_fillers)
        rest = raw.to_s.strip.sub(/\A\S+\s*/, "")
        strip_noun(rest, noun_fillers)
      end

      def strip_noun(text, noun_fillers)
        text.to_s.sub(/\A(?:#{noun_fillers.join('|')})\b\s*/i, "").strip
      end
    end
  end
end
