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
          when "game_resync"
            confirm_game_resync(payload)
          when "game_reindex"
            confirm_game_reindex(payload)
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

        # Enqueue a full IGDB resync for the game.
        def confirm_game_resync(payload)
          payload = payload.with_indifferent_access
          title   = payload[:game_title].to_s
          game    = ::Game.find_by(id: payload[:game_id])
          return Pito::Copy.render("pito.copy.games.not_found", { ref: title }) if game.nil?

          GameIgdbSync.perform_later(game.id)
          Pito::Copy.render("pito.copy.games.resync_queued", { title: title })
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
