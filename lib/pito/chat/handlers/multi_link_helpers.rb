# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Shared helpers for Link and Unlink follow-up branches.
      #
      # Both handlers need to:
      #   1. Detect the context (detail — singular id in payload; list — ids array).
      #   2. Split the rest string on a connector word (link: "to"/"with", unlink: "from").
      #   3. Parse source id (list context only) and a multi-target id list.
      #   4. Resolve each target, run the link/unlink operation, and produce a
      #      single summary Result::Ok system event.
      #
      # Callers include this module and call `follow_up_multi` with a block that
      # performs the per-target operation (link or unlink).
      module MultiLinkHelpers
        # Entry-point for follow-up link/unlink processing.
        #
        # @param connector [String]   regex fragment — "to" for link, "from" for unlink
        # @param source_class [Class] ::Video or ::Game (entity owning the source card)
        # @param other_class  [Class] the opposite class
        # @param source_nouns [Array<String>] noun fillers for the source class
        # @param other_nouns  [Array<String>] noun fillers for the other class
        # @param copy_ok   [String]  i18n key for summary success (single or multi)
        # @param copy_op   [Symbol]  :link or :unlink (drives the operation)
        # @return [Pito::Chat::Result::Ok | Pito::Chat::Result::Error]
        def follow_up_multi(connectors:, source_class:, other_class:, source_nouns:, other_nouns:, copy_ok:, copy_op:)
          payload = follow_up.source_event.payload.with_indifferent_access

          detail_id_key = detail_id_key_for(source_class)
          is_detail     = payload[detail_id_key].present?

          # Split on any accepted connector word (link: "to"/"with", unlink: "from").
          connector_re = /\b(?:#{connectors.map { |c| Regexp.escape(c) }.join('|')})\b/i
          parts        = follow_up.rest.to_s.strip.split(connector_re, 2)

          if is_detail
            # DETAIL: source is the card's entity; targets = everything after connector
            # (or the full rest minus a leading noun/connector if no connector typed).
            source_record = source_class.find_by(id: payload[detail_id_key])
            return not_found_for(source_class, "") if source_record.nil?

            targets_text = if parts.size >= 2
              parts[1].strip
            else
              # No connector typed — strip an optional leading connector word and noun
              rest_clean = follow_up.rest.to_s.strip
              rest_clean = rest_clean.sub(/\A(?:#{connectors.map { |c| Regexp.escape(c) }.join('|')})\b\s*/i, "")
              rest_clean = rest_clean.sub(/\A(?:#{(source_nouns + other_nouns).join('|')})\b\s*/i, "")
              rest_clean
            end
          else
            # LIST: source id is on the LEFT of the connector; targets on the RIGHT.
            return follow_up_usage(is_detail: false, copy_op: copy_op) if parts.size < 2

            left_text = parts[0].strip
            # Strip leading noun filler from left.
            left_clean = left_text.sub(/\A(?:#{source_nouns.join('|')})\b\s*/i, "")
            left_id    = left_clean.delete_prefix("#").strip
            return usage_hint unless left_id.match?(/\A\d+\z/)

            source_record = source_class.find_by(id: left_id)
            return not_found_for(source_class, left_id) if source_record.nil?

            targets_text = parts[1].strip
          end

          # Parse targets_text into a deduped list of numeric ids.
          # Strip a leading noun filler (other entity noun).
          targets_text = targets_text.to_s.sub(/\A(?:#{other_nouns.join('|')})\b\s*/i, "")
          raw_ids      = targets_text.split(/[\s,]+/).map(&:strip).select { |t| t.match?(/\A#?\d+\z/) }
          target_ids   = raw_ids.map { |t| t.delete_prefix("#") }.uniq

          return follow_up_usage(is_detail: is_detail, copy_op: copy_op) if target_ids.empty?

          # Resolve each target and perform the operation.
          linked_titles   = []
          unlinked_titles = []
          not_found_ids   = []

          target_ids.each do |tid|
            record = other_class.find_by(id: tid)
            if record.nil?
              not_found_ids << tid
              next
            end

            game, video = assign_roles(source_record, record, source_class)

            case copy_op
            when :link
              VideoGameLink.find_or_create_by!(video: video, game: game)
              linked_titles << record.title
            when :unlink
              link = VideoGameLink.find_by(video: video, game: game)
              link&.destroy
              unlinked_titles << record.title
            end
          end

          # Build summary message.
          targets_label = (linked_titles + unlinked_titles).join(", ")
          targets_label = not_found_ids.first if targets_label.blank?

          if linked_titles.empty? && unlinked_titles.empty?
            # All ids were not found.
            return not_found_for(other_class, not_found_ids.join(", "))
          end

          text = I18n.t(
            copy_ok,
            source:  source_record.title,
            targets: targets_label
          )

          if not_found_ids.any?
            text += " (not found: #{not_found_ids.join(', ')})"
          end

          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { "text" => text } }
          ])
        end

        private

        # Context-appropriate usage for a malformed follow-up link/unlink — shows
        # the REPLY syntax, not the free-chat noun form.
        def follow_up_usage(is_detail:, copy_op:)
          scope = is_detail ? "detail" : "list"
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.#{copy_op}.follow_up_usage.#{scope}",
            message_args: {}
          )
        end

        # Returns the payload key for the singular detail id.
        def detail_id_key_for(klass)
          case klass.name
          when "Video" then "video_id"
          when "Game"  then "game_id"
          end
        end

        # Returns [game, video] by resolving which argument is Game and which is Video.
        def assign_roles(source_record, other_record, source_class)
          if source_class == ::Video
            [ other_record, source_record ] # game, video
          else
            [ source_record, other_record ] # game, video
          end
        end

        def not_found_for(klass, ref)
          if klass == ::Game
            not_found_game(ref)
          else
            not_found_video(ref)
          end
        end
      end
    end
  end
end
