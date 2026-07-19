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
    #   "nl_run"     — the NL gate's did-you-mean confirm (see #confirm_nl_run):
    #                  confirm re-enters Pito::Dispatch::Router with the payload's
    #                  `nl_command`; cancel falls through to the generic
    #                  `pito.copy.confirmation.cancelled` message (no special case).
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
          when "video_schedule_mass"
            confirm_video_schedule_mass(payload)
          when "video_metadata"
            confirm_video_metadata(payload)
          when "video_metadata_mass"
            confirm_video_metadata_mass(payload)
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
          when "sync_game"
            confirm_sync_game(payload)
          when "nl_run"
            confirm_nl_run(payload)
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

        # `update vid description/tags <id> …` — the staged value lands locally,
        # then the write-through pushes ONLY that field (part=snippet, other
        # fields untouched via the fresh-snapshot overlay in VideosClient).
        def confirm_video_metadata(payload)
          payload = payload.with_indifferent_access
          title   = payload[:video_title].to_s
          field   = payload[:field].to_s
          video   = ::Video.find_by(id: payload[:video_id])
          return Pito::Copy.render("pito.copy.videos.not_found", { ref: title }) if video.nil?
          return Pito::Copy.render("pito.copy.confirmation.confirmed") unless %w[description tags].include?(field)

          value = payload[:staged_value]
          video.update!(field => field == "tags" ? Array(value).map(&:to_s) : value.to_s)
          VideoEmbedIndexJob.perform_later(video.id)
          VideoRemoteStatusSync.perform_later(video.id, fields: [ field ])
          Pito::Copy.render("pito.copy.videos.metadata_updated", { title: title, field: field })
        end

        # `update vid description/tags <id> <v>, <id> <v>, …` mass confirm
        # (WP4). PER ROW, deliberately NO transaction — unlike the mass
        # schedule form (all-or-nothing), a mass metadata batch is a set of
        # independent single-field writes, so one row vanishing between
        # staging and confirming (rare: the chat handler already filtered to
        # rows that resolved at STAGE time) shouldn't cost the rows around it.
        # A missing vid is a collected failure, never a raise. The outcome
        # text reports both counts — see pito.copy.update.mass_metadata_* for
        # the all-updated / all-failed / partial shapes.
        def confirm_video_metadata_mass(payload)
          payload = payload.with_indifferent_access
          field   = payload[:field].to_s
          return Pito::Copy.render("pito.copy.confirmation.confirmed") unless %w[description tags].include?(field)

          items = Array(payload[:items]).map { |item| item.with_indifferent_access }

          updated_count = 0
          failed_count  = 0

          items.each do |item|
            video = ::Video.find_by(id: item[:video_id])
            if video.nil?
              failed_count += 1
              next
            end

            value = item[:staged_value]
            video.update!(field => field == "tags" ? Array(value).map(&:to_s) : value.to_s)
            VideoEmbedIndexJob.perform_later(video.id)
            VideoRemoteStatusSync.perform_later(video.id, fields: [ field ])
            updated_count += 1
          end

          if failed_count.zero?
            Pito::Copy.render("pito.copy.update.mass_metadata_updated", { count: updated_count, field: field })
          elsif updated_count.zero?
            Pito::Copy.render("pito.copy.update.mass_metadata_failed", { count: failed_count, field: field })
          else
            Pito::Copy.render("pito.copy.update.mass_metadata_partial",
                               { updated: updated_count, field: field, failed: failed_count })
          end
        end

        def confirm_video_unlist(payload)
          payload = payload.with_indifferent_access
          title   = payload[:video_title].to_s
          video   = ::Video.find_by(id: payload[:video_id])
          return Pito::Copy.render("pito.copy.videos.not_found", { ref: title }) if video.nil?

          # Clear publish_at: a video carrying a scheduled publish time (a prior
          # `schedule`) is `private` + publish_at on YouTube. Flipping only
          # privacy_status to unlisted leaves the stale publish_at, and YouTube
          # rejects the pair (`invalidPublishAt` — publish_at is valid only while
          # private). Unlisting cancels any pending schedule, same as publish.
          video.update!(privacy_status: :unlisted, publish_at: nil)
          VideoRemoteStatusSync.perform_later(video.id)
          Pito::Copy.render("pito.copy.videos.unlisted", { title: title })
        end

        def confirm_video_schedule(payload)
          payload    = payload.with_indifferent_access
          title      = payload[:video_title].to_s
          video      = ::Video.find_by(id: payload[:video_id])
          return Pito::Copy.render("pito.copy.videos.not_found", { ref: title }) if video.nil?

          publish_at = Time.iso8601(payload[:publish_at].to_s)
          video.assign_attributes(privacy_status: :private, publish_at: publish_at)

          # :schedule-context save — the chat handler already dry-ran this same
          # validation at stage time, but the confirm click may land minutes
          # later (another schedule could have landed on the channel meanwhile,
          # or the vid could have gone public on YouTube in the interim), so
          # BOTH the eligibility and the collision checks run again here, for
          # real, at save time. Rescued locally (never re-raised) so this NEVER
          # falls through to the generic `pito.copy.confirmation.execution_failed`
          # rescue in Pito::FollowUp::Handlers::Confirmation — each failure gets
          # its own witty, specific outcome text instead.
          begin
            video.save!(context: :schedule)
          rescue ActiveRecord::RecordInvalid
            if video.already_published?
              return Pito::Copy.render("pito.copy.videos.schedule_already_public", { title: title })
            end

            collision = video.publish_spacing_collision
            return Pito::Copy.render("pito.copy.videos.schedule_conflict", {
              title: title,
              other: collision&.title.to_s,
              when:  Pito::Formatter::SyncStamp.call(collision&.publish_at)
            })
          end

          VideoRemoteStatusSync.perform_later(video.id)
          # Render the confirmed time in the app-local zone (Time.zone), matching
          # the house stamp the schedule confirmation showed. No "UTC" label —
          # a timezone is configured, so the time already reads local.
          when_label = Pito::Formatter::SyncStamp.call(publish_at)
          Pito::Copy.render("pito.copy.videos.scheduled",
                            { title: title, when: when_label })
        end

        # `schedule <id> <when>, <id> <when>, …` mass confirm (WP3). All-or-nothing,
        # confirm-time re-validation BY CONSTRUCTION: items are applied ascending by
        # publish_at inside ONE transaction, `find → assign → save!(context:
        # :schedule)` each. An earlier item's save is visible to a later item's own
        # publish_spacing_within_channel query (same transaction, same connection),
        # so an intra-batch collision — the stage-time handler's in-memory pairwise
        # check, re-run for real, or a NEW schedule that landed on the channel
        # between staging and confirming — is caught for free; no separate pairwise
        # logic needed here. Any failure rolls back EVERY item in the batch (nothing
        # partially scheduled) and names the vid that tripped it.
        # VideoRemoteStatusSync only fires after a clean, full commit.
        def confirm_video_schedule_mass(payload)
          payload = payload.with_indifferent_access
          items   = Array(payload[:items]).map { |item| item.with_indifferent_access }
                                           .sort_by { |item| Time.iso8601(item[:publish_at].to_s) }

          scheduled = []
          failure   = nil

          ActiveRecord::Base.transaction do
            items.each do |item|
              video = ::Video.find_by(id: item[:video_id])
              if video.nil?
                failure = { key: "pito.copy.videos.not_found", args: { ref: item[:video_title].to_s } }
                raise ActiveRecord::Rollback
              end

              video.assign_attributes(privacy_status: :private, publish_at: Time.iso8601(item[:publish_at].to_s))
              begin
                video.save!(context: :schedule)
              rescue ActiveRecord::RecordInvalid
                if video.already_published?
                  failure = { key: "pito.copy.videos.mass_schedule_already_public", args: { title: video.title } }
                  raise ActiveRecord::Rollback
                end

                collision = video.publish_spacing_collision
                failure = { key: "pito.copy.videos.mass_schedule_conflict", args: {
                  title: video.title,
                  other: collision&.title.to_s,
                  when:  Pito::Formatter::SyncStamp.call(collision&.publish_at)
                } }
                raise ActiveRecord::Rollback
              end

              scheduled << video
            end
          end

          return Pito::Copy.render(failure[:key], failure[:args]) if failure

          scheduled.each { |video| VideoRemoteStatusSync.perform_later(video.id) }
          Pito::Copy.render("pito.copy.videos.mass_scheduled", { count: scheduled.size })
        end

        # Force a synchronous reindex for the game (digest-bypassed).
        # We call the indexer inline rather than enqueuing so the confirmation
        # outcome text is accurate: "reindexed" means it's done, not "queued".
        # The executor runs inside FollowUpDispatchJob (already on a worker), so
        # a brief embedder HTTP call here is acceptable.
        def confirm_game_reindex(payload)
          payload = payload.with_indifferent_access
          title   = payload[:game_title].to_s
          game    = ::Game.find_by(id: payload[:game_id])
          return Pito::Copy.render("pito.copy.games.not_found", { ref: title }) if game.nil?

          ::Game::EmbeddingIndexer.call(game, force: true)
          Pito::Copy.render("pito.copy.games.reindexed", { title: title })
        end

        # Force a synchronous reindex for the video (digest-bypassed).
        # Mirrors confirm_game_reindex: we call the indexer inline rather than
        # enqueuing so the confirmation outcome text is accurate — "reindexed" means
        # it's already done. The executor runs inside FollowUpDispatchJob (on a
        # worker), so a brief embedder HTTP call is acceptable.
        def confirm_video_reindex(payload)
          payload = payload.with_indifferent_access
          title   = payload[:video_title].to_s
          video   = ::Video.find_by(id: payload[:video_id])
          return Pito::Copy.render("pito.copy.videos.not_found", { ref: title }) if video.nil?

          ::Video::EmbeddingIndexer.call(video, force: true)
          Pito::Copy.render("pito.copy.videos.reindexed", { title: title })
        end

        # ── sync_videos ────────────────────────────────────────────────────────────
        # Whole-channel form fans out ONE SyncVideosJob per channel (isolated; one
        # summary each). Targeted (`video_ids`) stays a single cross-channel job.
        # Returns a present-tense queued ack; each async job emits its own summary.
        def confirm_sync_videos(payload)
          payload         = payload.with_indifferent_access
          scope_label     = payload[:scope_label].to_s
          video_ids       = Array(payload[:video_ids])
          conversation_id = payload[:conversation_id].presence

          if video_ids.any?
            SyncVideosJob.perform_later(Array(payload[:channel_ids]), scope_label, conversation_id: conversation_id, video_ids: video_ids)
            # Targeted: scope_label is the id list (e.g. "#25") — phrase it as the
            # ids, not "%{scope} vids" (which read as "#25 vids").
            Pito::Copy.render("pito.copy.sync.videos_queued_targeted", { vids: scope_label })
          else
            fan_out_channels(payload[:channel_ids]) do |channel|
              SyncVideosJob.perform_later([ channel.id ], channel.at_handle, conversation_id: conversation_id)
            end
            Pito::Copy.render("pito.copy.sync.videos_queued", { scope: scope_label })
          end
        end

        # ── sync_channel ───────────────────────────────────────────────────────────
        # Fans out one SyncChannelJob PER channel (isolated; one output each).
        def confirm_sync_channel(payload)
          payload         = payload.with_indifferent_access
          scope_label     = payload[:scope_label].to_s
          conversation_id = payload[:conversation_id].presence
          fan_out_channels(payload[:channel_ids]) do |channel|
            SyncChannelJob.perform_later([ channel.id ], channel.at_handle, conversation_id: conversation_id)
          end
          Pito::Copy.render("pito.copy.sync.channel_queued", { scope: scope_label })
        end

        # ── sync_channel_videos ────────────────────────────────────────────────────
        # Fans out one SyncChannelVideosJob PER channel (isolated; one output each).
        def confirm_sync_channel_videos(payload)
          payload         = payload.with_indifferent_access
          scope_label     = payload[:scope_label].to_s
          conversation_id = payload[:conversation_id].presence
          fan_out_channels(payload[:channel_ids]) do |channel|
            SyncChannelVideosJob.perform_later([ channel.id ], channel.at_handle, conversation_id: conversation_id)
          end
          Pito::Copy.render("pito.copy.sync.channel_videos_queued", { scope: scope_label })
        end

        # ── sync_game ────────────────────────────────────────────────────────────
        # Enqueue the chat-initiated IGDB sync for one game. SyncGameJob runs the
        # IGDB sync then broadcasts its own summary turn.
        def confirm_sync_game(payload)
          payload = payload.with_indifferent_access
          title   = payload[:game_title].to_s
          game    = ::Game.find_by(id: payload[:game_id])
          return Pito::Copy.render("pito.copy.games.not_found", { ref: title }) if game.nil?

          SyncGameJob.perform_later(game.id, conversation_id: payload[:conversation_id].presence)
          Pito::Copy.render("pito.copy.sync.game_queued", { title: title })
        end

        # ── nl_run (the NL gate's did-you-mean confirm) ───────────────────────────
        # The ONLY command here that re-enters the real dispatch path rather than
        # touching a model directly — Pito::Chat::Handlers::Unknown's did-you-mean
        # branch (lib/pito/chat/handlers/unknown.rb) stamps `nl_command` (the
        # canonicalized command string) + `conversation_id` onto the confirmation
        # payload; on confirm we run it through Pito::Dispatch::Router exactly like
        # a typed command (mirrors Pito::FollowUp::ToolDelegator), then project the
        # resulting events into ONE outcome_text string via Pito::Mcp::EventText —
        # the same events → text projection the AI orchestrator uses to read a
        # dispatch result back. Degrades to the `huh` copy (K2) rather than raising
        # when the conversation is gone or the command comes back empty.
        def confirm_nl_run(payload)
          payload      = payload.with_indifferent_access
          command      = payload[:nl_command].to_s
          conversation = ::Conversation.find_by(id: payload[:conversation_id])
          return Pito::Copy.render("pito.copy.huh") if conversation.nil? || command.blank?

          # `nl_retry: true` — the NL loop guard (3.0.1 P7): a confirmed mapped
          # command that itself soft-fails must return its marker (rendered
          # below as its own crisp error text), never re-enter the NL gate —
          # otherwise confirm → soft-fail → gate → the SAME did-you-mean again,
          # a user-visible ping-pong with no terminal state.
          result = Pito::Dispatch::Router.call(input: command, conversation: conversation, nl_retry: true)
          events = Pito::Dispatch::Finalizer.result_events(result)
          Pito::Mcp::EventText.call(events).presence || Pito::Copy.render("pito.copy.huh")
        end

        # Resolve a sync scope (`channel_ids` empty = all connected channels) to
        # Channel records and yield each, so callers enqueue one isolated
        # per-channel job apiece. Mirrors the jobs' own scope resolution.
        def fan_out_channels(channel_ids)
          ids = Array(channel_ids).map(&:to_i).select(&:positive?)
          scope =
            if ids.empty?
              ::Channel.joins(:youtube_connection).order(:title)
            else
              ::Channel.where(id: ids).order(:title)
            end
          scope.each { |channel| yield channel }
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
          outcome = I18n.t("pito.slash.disconnect.confirmation.confirmed",
                           handle: handle, count: video_count)
          art = Pito::Copy.render("pito.copy.youtube.ascii_art")
          [ outcome, art ].compact.join("<br>").html_safe
        end
      end
    end
  end
end
