# frozen_string_literal: true

module Pito
  module Confirmation
    # Executes the confirmed or cancelled branch of a pending confirmation event.
    #
    # == Contract
    #
    # Both public class methods receive the `command` string (from
    # `payload["command"]`) and the full payload hash, and return an
    # outcome_text String.
    #
    # == Supported commands
    #
    #   "disconnect" — confirm destroys the channel + any exclusive YoutubeConnection;
    #                  cancel returns a human-readable cancellation message.
    #
    # == Error handling
    #
    # Callers should rescue StandardError and emit an error outcome_text via the
    # `pito.copy.confirmation.execution_failed` i18n key.
    class Executor
      class << self
        # Execute the confirm branch for the given command + payload.
        #
        # @param command [String] e.g. "disconnect"
        # @param payload [Hash]   the confirmation event payload (string or symbol keys).
        # @return [String] human-readable outcome text.
        def confirm(command, payload)
          case command.to_s
          when "disconnect"
            confirm_disconnect(payload)
          when "game_delete"
            confirm_game_delete(payload)
          when "video_delete"
            confirm_video_delete(payload)
          when "video_publish"
            confirm_video_publish(payload)
          when "video_unlist"
            confirm_video_unlist(payload)
          when "video_schedule"
            confirm_video_schedule(payload)
          when "game_reindex"
            confirm_game_reindex(payload)
          when "video_reindex"
            confirm_video_reindex(payload)
          when "sync_videos"
            confirm_sync_videos(payload)
          when "sync_channel"
            confirm_sync_channel(payload)
          when "sync_channel_videos"
            confirm_sync_channel_videos(payload)
          when "import_videos"
            confirm_import_videos(payload)
          else
            Pito::Copy.render("pito.copy.confirmation.confirmed")
          end
        end

        # Execute the cancel branch for the given command + payload.
        #
        # @param command [String] e.g. "disconnect"
        # @param payload [Hash]   the confirmation event payload (string or symbol keys).
        # @return [String] human-readable outcome text.
        def cancel(command, payload)
          case command.to_s
          when "disconnect"
            payload = payload.with_indifferent_access
            channel = ::Channel.find_by(id: payload[:channel_id])
            handle  = channel&.handle&.presence || channel&.title.to_s
            Pito::Copy.render("pito.copy.disconnect.cancelled",
                              { handle: handle.presence || I18n.t("pito.confirmation.channel_fallback") })
          else
            Pito::Copy.render("pito.copy.confirmation.cancelled")
          end
        end

        private

        def confirm_game_delete(payload)
          payload = payload.with_indifferent_access
          title   = payload[:game_title].to_s
          ::Game.find_by(id: payload[:game_id])&.destroy!
          Pito::Copy.render("pito.copy.games.deleted", { title: title })
        end

        def confirm_video_delete(payload)
          payload = payload.with_indifferent_access
          title   = payload[:video_title].to_s
          video   = ::Video.find_by(id: payload[:video_id])

          if video
            yt_id   = video.youtube_video_id
            conn_id = video.channel&.youtube_connection_id
            video.destroy!
            VideoRemoteDelete.perform_later(yt_id, conn_id) if yt_id.present? && conn_id.present?
          end

          Pito::Copy.render("pito.copy.videos.deleted_remote", { title: title })
        end

        def confirm_video_publish(payload)
          payload = payload.with_indifferent_access
          title   = payload[:video_title].to_s
          video   = ::Video.find_by(id: payload[:video_id])
          return Pito::Copy.render("pito.copy.videos.not_found", { ref: title }) if video.nil?

          video.update!(privacy_status: :public, publish_at: nil)
          VideoRemoteStatusSync.perform_later(video.id)
          Pito::Copy.render("pito.copy.videos.published", { title: title })
        end

        def confirm_video_unlist(payload)
          payload = payload.with_indifferent_access
          title   = payload[:video_title].to_s
          video   = ::Video.find_by(id: payload[:video_id])
          return Pito::Copy.render("pito.copy.videos.not_found", { ref: title }) if video.nil?

          video.update!(privacy_status: :unlisted)
          VideoRemoteStatusSync.perform_later(video.id)
          Pito::Copy.render("pito.copy.videos.unlisted", { title: title })
        end

        def confirm_video_schedule(payload)
          payload    = payload.with_indifferent_access
          title      = payload[:video_title].to_s
          video      = ::Video.find_by(id: payload[:video_id])
          return Pito::Copy.render("pito.copy.videos.not_found", { ref: title }) if video.nil?

          publish_at = Time.iso8601(payload[:publish_at].to_s)
          video.update!(privacy_status: :private, publish_at: publish_at)
          VideoRemoteStatusSync.perform_later(video.id)
          Pito::Copy.render("pito.copy.videos.scheduled",
                            { title: title, when: publish_at.strftime("%Y-%m-%d %H:%M UTC") })
        end

        # Force a synchronous Voyage reindex for the game (digest-bypassed).
        # We call the indexer inline rather than enqueuing so the confirmation
        # outcome text is accurate: "reindexed" means it's done, not "queued".
        # The executor runs inside FollowUpDispatchJob (already on a worker), so
        # a brief Voyage HTTP call here is acceptable.
        def confirm_game_reindex(payload)
          payload = payload.with_indifferent_access
          title   = payload[:game_title].to_s
          game    = ::Game.find_by(id: payload[:game_id])
          return Pito::Copy.render("pito.copy.games.not_found", { ref: title }) if game.nil?

          ::Game::VoyageIndexer.call(game, force: true)
          Pito::Copy.render("pito.copy.games.reindexed", { title: title })
        end

        # Force a synchronous Voyage reindex for the video (digest-bypassed).
        # Mirrors confirm_game_reindex: we call the indexer inline rather than
        # enqueuing so the confirmation outcome text is accurate — "reindexed" means
        # it's already done. The executor runs inside FollowUpDispatchJob (on a
        # worker), so a brief Voyage HTTP call is acceptable.
        def confirm_video_reindex(payload)
          payload = payload.with_indifferent_access
          title   = payload[:video_title].to_s
          video   = ::Video.find_by(id: payload[:video_id])
          return Pito::Copy.render("pito.copy.videos.not_found", { ref: title }) if video.nil?

          ::Video::VoyageIndexer.call(video, force: true)
          Pito::Copy.render("pito.copy.videos.reindexed", { title: title })
        end

        # ── sync_videos ────────────────────────────────────────────────────────────
        # Enqueues SyncVideosJob for the resolved channel scope.
        # Returns a present-tense queued ack; the async job emits the done summary
        # with the real count once it finishes.
        def confirm_sync_videos(payload)
          payload         = payload.with_indifferent_access
          scope_label     = payload[:scope_label].to_s
          channel_ids     = Array(payload[:channel_ids])
          conversation_id = payload[:conversation_id].presence
          SyncVideosJob.perform_later(channel_ids, scope_label, conversation_id: conversation_id)
          Pito::Copy.render("pito.copy.sync.videos_queued", { scope: scope_label })
        end

        # ── sync_channel ───────────────────────────────────────────────────────────
        # Enqueues SyncChannelJob for the resolved channel scope.
        def confirm_sync_channel(payload)
          payload         = payload.with_indifferent_access
          scope_label     = payload[:scope_label].to_s
          channel_ids     = Array(payload[:channel_ids])
          conversation_id = payload[:conversation_id].presence
          SyncChannelJob.perform_later(channel_ids, scope_label, conversation_id: conversation_id)
          Pito::Copy.render("pito.copy.sync.channel_queued", { scope: scope_label })
        end

        # ── sync_channel_videos ────────────────────────────────────────────────────
        # Enqueues SyncChannelVideosJob for the resolved channel scope.
        def confirm_sync_channel_videos(payload)
          payload         = payload.with_indifferent_access
          scope_label     = payload[:scope_label].to_s
          channel_ids     = Array(payload[:channel_ids])
          conversation_id = payload[:conversation_id].presence
          SyncChannelVideosJob.perform_later(channel_ids, scope_label, conversation_id: conversation_id)
          Pito::Copy.render("pito.copy.sync.channel_videos_queued", { scope: scope_label })
        end

        # ── import_videos ──────────────────────────────────────────────────────────
        # Enqueues ChatImportVideosJob for the resolved channel scope.
        def confirm_import_videos(payload)
          payload         = payload.with_indifferent_access
          scope_label     = payload[:scope_label].to_s
          channel_ids     = Array(payload[:channel_ids])
          conversation_id = payload[:conversation_id].presence
          ChatImportVideosJob.perform_later(channel_ids, scope_label, conversation_id: conversation_id)
          Pito::Copy.render("pito.copy.import_videos.queued", { scope: scope_label })
        end

        def confirm_disconnect(payload)
          payload       = payload.with_indifferent_access
          channel       = ::Channel.find_by(id: payload[:channel_id])
          return Pito::Copy.render("pito.copy.disconnect.already_gone") if channel.nil?

          handle        = channel.handle.presence || channel.title.to_s
          video_count   = channel.videos.count
          connection_id = channel.youtube_connection_id

          ActiveRecord::Base.transaction do
            channel.destroy!
            if connection_id && !::Channel.exists?(youtube_connection_id: connection_id)
              YoutubeConnection.find_by(id: connection_id)&.destroy
            end
          end

          # Intentional i18n (not Pito::Copy): pluralization requires count:, which
          # Pito::Copy.render does not support. This is the one exception in this executor.
          I18n.t("pito.slash.disconnect.confirmation.confirmed",
                 handle: handle, count: video_count)
        end
      end
    end
  end
end
