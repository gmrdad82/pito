# frozen_string_literal: true

module Pito
  module Chat
    # Declarative segment table for multi-segment verbs.
    #
    # This is the Ruby precursor of the future verbs.yml `segments:` config
    # (plan-0.9.5 D7). It must stay DATA-ONLY — no emission logic, no builder
    # invocations, no side effects. Callers own the loop; this file owns the
    # ordering + metadata.
    #
    # Each Segment records one scrollback message a verb emits for an entity:
    #   name         — dash-case identifier (matches verbs.yml key)
    #   builder      — the MessageBuilder class constant
    #   kind         — :system or :enhanced (event chrome)
    #   default      — true when the segment emits with a bare verb (no with/only)
    #   fill         — pending-fill job class constant, or nil
    #   reply_target — Symbol used by the follow-up dispatch table
    #   emit_if      — arity-1 lambda(entity_record) → Boolean, or nil (unconditional)
    class Segments
      Segment = Data.define(:name, :builder, :kind, :default, :fill, :reply_target, :emit_if)

      # Returns the ordered, frozen Array of Segments for a verb+entity pair.
      #
      # @param verb   [Symbol]  :show, :analyze (more verbs may be added to TABLE later)
      # @param entity [Symbol]  :channel, :vid, or :game
      # @return [Array<Segment>]
      # @raise [ArgumentError] on unknown verb or entity
      def self.for(verb:, entity:)
        table = TABLE.fetch(verb) { raise ArgumentError, "unknown verb: #{verb.inspect}" }
        table.fetch(entity) { raise ArgumentError, "unknown entity: #{entity.inspect} for verb: #{verb.inspect}" }
      end

      # @return [Array<String>] ordered dash-case segment names
      def self.names(verb:, entity:)
        self.for(verb:, entity:).map(&:name)
      end

      # @return [Array<String>] names of segments where default: true
      def self.default_names(verb:, entity:)
        self.for(verb:, entity:).select(&:default).map(&:name)
      end

      # Shared segment list for all three analyze entities. Defined once and
      # referenced by all three TABLE keys to guarantee identity equality.
      #
      # The analyze pipeline (Prepare/Metric jobs) owns its own fan-out — `fill`
      # stays nil; the builder creates ONE pending scaffold per segment
      # (role = system|enhanced); wiring lands in the next task (plan-0.9.5 T2.2).
      ANALYZE_SEGMENTS = [
        Segment.new(
          name:         "numbers",
          builder:      Pito::MessageBuilder::Analyze::Message,
          kind:         :system,
          default:      true,
          fill:         nil,
          reply_target: :analyze_message,
          emit_if:      nil
        ),
        Segment.new(
          name:         "breakdowns",
          builder:      Pito::MessageBuilder::Analyze::Message,
          kind:         :enhanced,
          default:      false,
          fill:         nil,
          reply_target: :analyze_message,
          emit_if:      nil
        )
      ].freeze

      TABLE = {
        show: {
          # ── show channel ───────────────────────────────────────────────────────
          # detail always; videos only when the channel has at least one video;
          # at-a-glance always (channel-level metrics need no linked videos).
          channel: [
            Segment.new(
              name:         "detail",
              builder:      Pito::MessageBuilder::Channel::Detail,
              kind:         :system,
              default:      true,
              fill:         nil,
              reply_target: :channel_detail,
              emit_if:      nil
            ),
            Segment.new(
              name:         "videos",
              builder:      Pito::MessageBuilder::Channel::Videos,
              kind:         :enhanced,
              default:      false,
              fill:         nil,
              reply_target: :video_list,
              emit_if:      ->(channel) { channel.videos.any? }
            ),
            Segment.new(
              name:         "at-a-glance",
              builder:      Pito::MessageBuilder::Analytics::Enhanced,
              kind:         :enhanced,
              default:      false,
              fill:         AnalyticsFillJob,
              reply_target: :analytics_glance,
              emit_if:      nil
            )
          ].freeze,

          # ── show vid ──────────────────────────────────────────────────────────
          # detail always; linked-game only when video.linked_games.first is
          # present (mirrors handler: truthy first-record check, not .any?);
          # at-a-glance always.
          vid: [
            Segment.new(
              name:         "detail",
              builder:      Pito::MessageBuilder::Video::Detail,
              kind:         :system,
              default:      true,
              fill:         nil,
              reply_target: :video_detail,
              emit_if:      nil
            ),
            Segment.new(
              name:         "linked-game",
              builder:      Pito::MessageBuilder::Video::LinkedGame,
              kind:         :enhanced,
              default:      false,
              fill:         nil,
              reply_target: :game_detail,
              emit_if:      ->(vid) { vid.linked_games.first.present? }
            ),
            Segment.new(
              name:         "at-a-glance",
              builder:      Pito::MessageBuilder::Analytics::Enhanced,
              kind:         :enhanced,
              default:      false,
              fill:         AnalyticsFillJob,
              reply_target: :analytics_glance,
              emit_if:      nil
            )
          ].freeze,

          # ── show game ─────────────────────────────────────────────────────────
          # detail → similar (always) → linked-videos (only when game has linked
          # videos) → channels (always, pending-fill) → at-a-glance (always,
          # pending-fill). Order matches handler: recommendations land first;
          # analytics (slowest) lands last.
          game: [
            Segment.new(
              name:         "detail",
              builder:      Pito::MessageBuilder::Game::Detail,
              kind:         :system,
              default:      true,
              fill:         nil,
              reply_target: :game_detail,
              emit_if:      nil
            ),
            Segment.new(
              name:         "similar",
              builder:      Pito::MessageBuilder::Game::SimilarGames,
              kind:         :enhanced,
              default:      false,
              fill:         nil,
              reply_target: :game_similar,
              emit_if:      nil
            ),
            Segment.new(
              name:         "linked-videos",
              builder:      Pito::MessageBuilder::Game::LinkedVideos,
              kind:         :enhanced,
              default:      false,
              fill:         nil,
              reply_target: :game_linked_videos,
              emit_if:      ->(game) { game.linked_videos.any? }
            ),
            Segment.new(
              name:         "channels",
              builder:      Pito::MessageBuilder::Game::Channels,
              kind:         :enhanced,
              default:      false,
              fill:         ChannelDistributionFillJob,
              reply_target: :game_channels,
              emit_if:      nil
            ),
            Segment.new(
              name:         "at-a-glance",
              builder:      Pito::MessageBuilder::Analytics::Enhanced,
              kind:         :enhanced,
              default:      false,
              fill:         AnalyticsFillJob,
              reply_target: :analytics_glance,
              emit_if:      nil
            )
          ].freeze
        }.freeze,

        # ── analyze ─────────────────────────────────────────────────────────────
        # All three entities share the same two segments (ANALYZE_SEGMENTS).
        analyze: {
          channel: ANALYZE_SEGMENTS,
          vid:     ANALYZE_SEGMENTS,
          game:    ANALYZE_SEGMENTS
        }.freeze
      }.freeze
    end
  end
end
