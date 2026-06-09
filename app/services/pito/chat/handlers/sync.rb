# frozen_string_literal: true

# Handler for the `sync` chat verb — noun-discriminated.
#
# Parses the noun phrase from `message.raw`:
#
#   sync game <ref>            → IGDB sync for one game
#   sync video <ref>           → YouTube sync for one video
#   sync videos                → YouTube sync for all videos on scoped channel(s)
#   sync channel               → channel fields + stats for scoped channel(s)
#   sync channel with videos   → channel + all their videos for scoped channel(s)
#
# Each path emits a `:confirmation` event carrying the relevant command and
# scope.  The actual work runs in the orchestrating job enqueued from
# `Pito::Confirmation::Executor`.
#
# Channel scope is read from `self.channel` (@all/blank = all channels,
# @handle = one channel; unknown handle = error message).
module Pito
  module Chat
    module Handlers
      class Sync < Pito::Chat::Handler
        self.verb = :sync
        self.description_key = "pito.chat.sync.descriptions.sync"

        GAME_NOUN_FILLERS  = %w[game games].freeze
        VIDEO_NOUN_FILLERS = %w[video videos].freeze

        def call
          raw = message.raw.to_s

          if channel_with_videos_form?(raw)
            handle_channel_videos
          elsif channel_form?(raw)
            handle_channel
          elsif videos_form?(raw)
            handle_videos
          elsif video_form?(raw)
            handle_video
          elsif game_form?(raw)
            handle_game
          else
            needs_ref
          end
        end

        private

        # ── Noun-form predicates ─────────────────────────────────────────────────

        # "sync channel with videos" — must be checked before channel_form?
        def channel_with_videos_form?(raw)
          raw.match?(/\bchannels?\s+with\s+videos?\b/i)
        end

        def channel_form?(raw)
          raw.match?(/\bchannels?\b/i)
        end

        def videos_form?(raw)
          # "sync videos" — plural only; "sync video <ref>" is the single-entity path
          raw.match?(/\bvideos\b/i)
        end

        def video_form?(raw)
          raw.match?(/\bvideos?\b/i)
        end

        def game_form?(raw)
          raw.match?(/\bgames?\b/i)
        end

        # ── Single-entity: game ──────────────────────────────────────────────────

        def handle_game
          game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUN_FILLERS)
          return needs_ref if game == :needs_ref
          return game_not_found(target_ref(GAME_NOUN_FILLERS, id_key: :game_id)) if game.nil?

          payload = Pito::MessageBuilder::Game::SyncConfirmation.call(game, conversation:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── Single-entity: video ─────────────────────────────────────────────────

        def handle_video
          video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUN_FILLERS)
          return needs_ref if video == :needs_ref
          return video_not_found(target_ref(VIDEO_NOUN_FILLERS, id_key: :video_id)) if video.nil?

          payload = Pito::MessageBuilder::Video::SyncConfirmation.call(video, conversation:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── Channel-scoped: sync videos ──────────────────────────────────────────

        def handle_videos
          scope_label, channel_ids, error = resolve_scope
          return error if error

          payload = Pito::MessageBuilder::Sync::VideosConfirmation.call(
            scope_label, channel_ids: channel_ids, conversation:
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── Channel-scoped: sync channel ─────────────────────────────────────────

        def handle_channel
          scope_label, channel_ids, error = resolve_scope
          return error if error

          payload = Pito::MessageBuilder::Sync::ChannelConfirmation.call(
            scope_label, channel_ids: channel_ids, conversation:
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── Channel-scoped: sync channel with videos ─────────────────────────────

        def handle_channel_videos
          scope_label, channel_ids, error = resolve_scope
          return error if error

          payload = Pito::MessageBuilder::Sync::ChannelVideosConfirmation.call(
            scope_label, channel_ids: channel_ids, conversation:
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── Scope resolution (mirrors List handler's channel_scoped_videos) ───────
        #
        # Returns [scope_label, channel_ids_array, nil] on success
        # or [nil, nil, Result::Ok(error event)] on unknown handle.
        # channel_ids is empty when scope is @all (all channels).
        def resolve_scope
          handle = resolved_channel_handle

          if handle.nil?
            # @all or blank → all channels
            return [ "all channels", [], nil ]
          end

          norm = normalized_handle(handle)
          ch   = ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)

          if ch.nil?
            error_payload = Pito::MessageBuilder::Text.call(
              "pito.copy.channels.not_found",
              handle: handle
            )
            return [ nil, nil, Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: error_payload }
            ]) ]
          end

          [ ch.handle.presence || handle, [ ch.id ], nil ]
        end

        # Returns the handle string for a specific channel, or nil for @all/blank.
        def resolved_channel_handle
          ch = channel.to_s.strip
          return nil if ch.blank? || ch.casecmp("@all").zero?

          ch
        end

        def normalized_handle(handle)
          handle.to_s.sub(/\A@+/, "")
        end

        # ── Error helpers ─────────────────────────────────────────────────────────

        def needs_ref
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.sync.needs_ref",
            message_args: {}
          )
        end

        def game_not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end

        def video_not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end
      end
    end
  end
end
