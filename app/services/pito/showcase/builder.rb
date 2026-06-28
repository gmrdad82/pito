# frozen_string_literal: true

module Pito
  module Showcase
    # Builds a 10–15 command showcase for the chatbox.
    #
    # Rule-based + deterministic — no Voyage. Called after every completed turn
    # and when a new conversation is seeded. Returns an ordered Array of
    # matrix-valid chat-verb command strings using REAL DB ids.
    #
    # Context is derived from the last COMPLETED turn's events' payloads
    # (which carry game_id / game_ids / video_id / video_ids / channel_id /
    # reply_target). Falls back to the seed set when there is no completed turn
    # or when payloads carry no recognisable entity context.
    #
    # == Usage
    #
    #   Pito::Showcase::Builder.call(conversation: conv)
    #   # => ["list games", "list vids", …]
    class Builder
      # Seed set for fresh conversations (no completed turns yet).
      SEED_COMMANDS = [
        "list channels",
        "list games",
        "list vids",
        "show last vid",
        "list games upcoming"
      ].freeze

      def self.call(conversation:)
        new(conversation:).call
      end

      def initialize(conversation:)
        @conversation = conversation
      end

      # @return [Array<String>] ordered 10–15 matrix-valid command strings.
      def call
        last_turn = @conversation.turns
          .where.not(completed_at: nil)
          .order(:position)
          .last

        return seed_set if last_turn.nil?

        build_context_set(last_turn)
      end

      private

      # Seed set returned when there is no context to build from.
      # Appends "sync channels" when channels are already connected.
      def seed_set
        cmds = SEED_COMMANDS.dup
        cmds << "sync channels" if ::Channel.exists?
        cmds.first(15)
      end

      # Build a context-aware set from the last turn's non-echo/thinking events.
      def build_context_set(turn)
        payloads = turn.events
          .where.not(kind: %w[echo thinking])
          .order(:position)
          .map(&:payload)

        return seed_set if payloads.empty?

        merged  = payloads.reduce({}) { |acc, p| acc.merge(p.stringify_keys) }
        context = detect_context(payloads, merged)

        generate_for_context(context, merged).uniq.first(15)
      end

      # Detect the primary context from the events' payloads.
      # reply_target is the most precise signal; falls back to key detection.
      # Returns a Symbol: :game_list, :game_detail, :video_list, :video_detail,
      # :channel_list, :channel_detail, or :generic.
      def detect_context(payloads, merged)
        payloads.each do |p|
          case p["reply_target"]
          when "game_list"     then return :game_list
          when "game_detail"   then return :game_detail
          when "video_list"    then return :video_list
          when "video_detail"  then return :video_detail
          when "channel_list"  then return :channel_list
          when "channel_detail" then return :channel_detail
          end
        end

        return :game_list    if merged.key?("game_ids")
        return :video_list   if merged.key?("video_ids")
        return :game_detail  if merged.key?("game_id")
        return :video_detail if merged.key?("video_id")
        return :channel_detail if merged.key?("channel_id")

        :generic
      end

      def generate_for_context(context, merged)
        case context
        when :game_list     then game_list_suggestions(merged)
        when :game_detail   then game_detail_suggestions(merged)
        when :video_list    then video_list_suggestions(merged)
        when :video_detail  then video_detail_suggestions(merged)
        when :channel_list  then channel_list_suggestions
        when :channel_detail then channel_detail_suggestions(merged)
        else                     seed_set
        end
      end

      # After `list games`: show specific games + navigation.
      # game_ids are taken from the list payload (up to 3 for the showcase).
      def game_list_suggestions(merged)
        game_ids = Array(merged["game_ids"]).first(3)
        cmds     = game_ids.map { |id| "show game ##{id}" }
        cmds + [
          "list games upcoming",
          "list channels",
          "list vids",
          "show last vid",
          "list games"
        ]
      end

      # After `show game #<id>`: footage update, analyze, link to recent vid.
      def game_detail_suggestions(merged)
        game_id = merged["game_id"]
        return seed_set unless game_id

        cmds = [
          "footage update ##{game_id} 2",
          "footage update ##{game_id} 4",
          "analyze games ##{game_id}"
        ]

        recent_video = ::Video.order(id: :desc).first
        cmds << "link vid ##{recent_video.id} to game ##{game_id}" if recent_video

        cmds + [
          "list games",
          "list vids",
          "show last vid"
        ]
      end

      # After `list vids`: show specific videos + navigation.
      def video_list_suggestions(merged)
        video_ids = Array(merged["video_ids"]).first(3)
        cmds      = video_ids.map { |id| "show vid ##{id}" }
        cmds + [
          "list games",
          "list channels",
          "show last vid",
          "list vids"
        ]
      end

      # After `show vid #<id>`: link to recent game, analyze, navigation.
      def video_detail_suggestions(merged)
        video_id = merged["video_id"]
        return seed_set unless video_id

        cmds = []

        recent_game = ::Game.order(id: :desc).first
        cmds << "link vid ##{video_id} to game ##{recent_game.id}" if recent_game

        cmds + [
          "analyze vids ##{video_id}",
          "show last vid",
          "list vids",
          "list games",
          "list channels"
        ]
      end

      # After `list channels`: show each channel + navigation.
      def channel_list_suggestions
        cmds = [
          "list vids",
          "list games",
          "show last vid",
          "list games upcoming"
        ]

        ::Channel.where.not(youtube_connection_id: nil).order(:handle).limit(3).each do |ch|
          cmds << "show channel #{ch.at_handle}"
        end

        cmds << "sync channels"
        cmds
      end

      # After `show channel @handle`: sync that channel + navigation.
      def channel_detail_suggestions(merged)
        channel_id = merged["channel_id"]
        cmds       = []

        if channel_id && (ch = ::Channel.find_by(id: channel_id))
          cmds << "sync #{ch.at_handle}"
          cmds << "analyze channel #{ch.at_handle}"
        end

        cmds + [
          "list vids",
          "list games",
          "show last vid",
          "list channels"
        ]
      end
    end
  end
end
