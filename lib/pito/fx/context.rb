# frozen_string_literal: true

module Pito
  module Fx
    # Derives the living background's CONTEXT for an eligible event (F2/F3 —
    # Option B): the event says WHAT it is (`{"context" => …, "covers" =>
    # [paths]}`), never which effect renders it — fx.yml owns that mapping.
    #
    # Eligible kinds: :system, :enhanced, :ai only. Replace-style follow-ups
    # mutate their source event in place, so re-deriving at the Broadcaster's
    # replace choke point keeps the stamp honest; new-message follow-ups are
    # ordinary events of their own kind (excluded by design).
    #
    # OWNER LAW (2026-07-13): single-cover moods (water/duotone/lens) belong to
    # ONE-entity messages only — show/analyze of ONE game or vid + their
    # sub-segments. Walls (cover_wall) belong to lists (ls games, ls vids) and
    # show channel. Everything else renders cover-less. Replies need no special
    # rules — a reply is judged by its own payload markers exactly like any
    # other message, so re-deriving on mutate/rerender stays honest.
    #
    # Discrimination reads the payload's existing entity markers (never new
    # ones), first match wins, ordered most-specific first:
    #   1. an "analyze"/"analytics" marker present → its OWN entity decides:
    #      channel → "analyze_channel" (cover-less by design); a SINGLE vid or
    #      game → "analyze_vid"/"analyze_game" (that entity's single :detail
    #      cover); anything else (breakdowns, multi-entity sweeps) → bare
    #      "analyze" (cover-less). The two marker shapes are normalised here:
    #      Pito::MessageBuilder::Analyze::Message carries
    #      {"level","entity_ids"}; Pito::MessageBuilder::Analytics::Enhanced
    #      (the at-a-glance card) carries {"scope_type","scope_id"|"scope_ids"}.
    #   2. channel_id (no analyze marker) → "channel" (a vid detail carries its
    #      linked game_id too, but a vid moment must still outrank it — see 3).
    #   3. video_id → "vid_detail" (single cover); video_ids → "vid_list" (wall).
    #   4. game_id → "game_detail" (single cover); game_ids → "game_list" (wall).
    #
    # Covers are Active Storage variant PATHS (host-independent): :detail for
    # single-cover moods, :strip for walls (capped at WALL_COVERS_MAX). A game
    # without art contributes nothing — pools that need covers degrade to the
    # sky client-side.
    module Context
      ELIGIBLE_KINDS  = %w[system enhanced ai].freeze
      WALL_COVERS_MAX = 14

      # Analytics::Enhanced's scope_type (a Ruby class name string) → the same
      # level vocabulary Analyze::Message already uses ("channel"/"vid"/"game").
      SCOPE_TYPE_LEVELS = { "Channel" => "channel", "Video" => "vid", "Game" => "game" }.freeze

      module_function

      def eligible?(kind)
        ELIGIBLE_KINDS.include?(kind.to_s)
      end

      # @return [Hash, nil] `{"context" => String, "covers" => [String]}`, or
      #   nil when the event carries no mood (the sky answers — F1).
      def derive(kind:, payload:)
        return nil unless eligible?(kind)
        return ai_context(payload) if kind.to_s == "ai"
        return nil unless payload.is_a?(Hash)

        analyze_context(payload) || entity_context(payload)
      end

      # An AI answer that references EXACTLY ONE game (media blocks,
      # entity: game) wears that game's cover — the ai_game context, glow's
      # exclusive home (owner 2026-07-13). Anything else — zero games, many
      # games, vids-only, or the pending shell before the blocks land —
      # stays the cover-less "ai". replace_event's re-derive flips the
      # finished answer to ai_game the moment its blocks arrive.
      def ai_context(payload)
        game_ids = ai_game_ids(payload)
        if game_ids.size == 1
          { "context" => "ai_game", "covers" => game_covers(game_ids, variant: :detail) }
        else
          { "context" => "ai", "covers" => [] }
        end
      end

      # A game reference in an AI answer: a media block (entity: game) OR a
      # suggestion block whose command names a game id ("show game 12",
      # "update game footage 12 4"...). The owner's five real AI answers
      # carried zero media blocks — suggestions are how answers actually
      # point at games in practice.
      SUGGESTION_GAME_ID = /\bgame\s+(?:footage\s+|price\s+|platform\s+)?#?(\d+)/

      def ai_game_ids(payload)
        return [] unless payload.is_a?(Hash)

        Array(payload["blocks"]).flat_map do |block|
          next [] unless block.is_a?(Hash)

          case block["type"].to_s
          when "media"
            block["entity"].to_s == "game" ? [ block["id"] ] : []
          when "suggestion"
            block["command"].to_s.scan(SUGGESTION_GAME_ID).flatten.map(&:to_i)
          else
            []
          end
        end.compact.uniq
      end

      # The analyze/analytics marker's own entity, normalised across both
      # marker shapes (see the module doc above). Returns nil when neither
      # marker is present, so callers fall through to the plain entity markers.
      def analyze_context(payload)
        marker = payload["analyze"]
        marker = payload["analytics"] unless marker.present?
        return nil unless marker.present?

        level, ids = analyze_entity(marker)
        case level
        when "channel" then { "context" => "analyze_channel", "covers" => channel_covers(ids.first) }
        when "vid"      then single_analyze("analyze_vid", ids) { |i| vid_covers(i, variant: :detail) }
        when "game"     then single_analyze("analyze_game", ids) { |i| game_covers(i, variant: :detail) }
        else bare_analyze
        end
      end

      # [level, ids] from either marker shape: Analyze::Message's own
      # {"level","entity_ids"}, or Analytics::Enhanced's {"scope_type",
      # "scope_id"|"scope_ids"} (scope_ids for the multi-entity at-a-glance).
      def analyze_entity(marker)
        return [ marker["level"], Array(marker["entity_ids"]) ] if marker.key?("level")

        level = SCOPE_TYPE_LEVELS[marker["scope_type"]]
        ids   = marker["scope_ids"].presence || Array(marker["scope_id"])
        [ level, Array(ids) ]
      end

      # A SINGLE resolved entity gets its own single-cover mood; anything else
      # (zero or many — breakdowns, multi-entity sweeps) falls back to the
      # bare cover-less "analyze" context.
      def single_analyze(context, ids)
        return bare_analyze unless ids.size == 1

        { "context" => context, "covers" => yield(ids) }
      end

      def bare_analyze
        { "context" => "analyze", "covers" => [] }
      end

      def entity_context(payload)
        if payload["channel_id"].present?
          { "context" => "channel", "covers" => channel_covers(payload["channel_id"]) }
        elsif payload["video_id"].present?
          { "context" => "vid_detail", "covers" => vid_covers([ payload["video_id"] ], variant: :detail) }
        elsif payload["video_ids"].present?
          { "context" => "vid_list",
            "covers" => vid_covers(payload["video_ids"], variant: :strip).first(WALL_COVERS_MAX) }
        elsif payload["game_id"].present?
          { "context" => "game_detail", "covers" => game_covers([ payload["game_id"] ], variant: :detail) }
        elsif payload["game_ids"].present?
          { "context" => "game_list",
            "covers" => game_covers(payload["game_ids"].first(WALL_COVERS_MAX), variant: :strip) }
        end
      end

      def game_covers(ids, variant:)
        ::Game.where(id: ids).includes(cover_art_attachment: :blob).filter_map do |game|
          cover_path(game, variant)
        end
      end

      # A vid's mood is its linked game's art (owner: game from the vid).
      def vid_covers(ids, variant:)
        game_ids = ::VideoGameLink.where(video_id: ids).distinct.pluck(:game_id)
        game_covers(game_ids, variant:)
      end

      # A channel's wall is the games it covers through its vids' links (#14).
      # Art-bearing games only, IN SQL — an art-less game must never spend one
      # of the wall's LIMIT slots (found by the T10.7 spec round: 13/14 walls).
      def channel_covers(channel_id)
        game_ids = ::Game.joins(video_game_links: :video)
                         .joins(cover_art_attachment: :blob)
                         .where(videos: { channel_id: channel_id })
                         .distinct.limit(WALL_COVERS_MAX).pluck(:id)
        game_covers(game_ids, variant: :strip)
      end

      def cover_path(game, variant)
        return nil unless game.cover_art.attached?

        Rails.application.routes.url_helpers.rails_representation_path(
          game.cover_art.variant(variant), only_path: true
        )
      rescue StandardError
        nil
      end
    end
  end
end
