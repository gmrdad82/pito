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
    # `pito.confirmation.errors.execution_failed` i18n key.
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
          else
            I18n.t("pito.confirmation.confirmed.default")
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
            channel = Channel.find_by(id: payload[:channel_id])
            handle  = channel&.handle&.presence || channel&.title.to_s
            I18n.t("pito.slash.disconnect.confirmation.cancelled",
                   handle: handle.presence || "the channel")
          else
            I18n.t("pito.confirmation.cancelled.default")
          end
        end

        private

        def confirm_disconnect(payload)
          payload       = payload.with_indifferent_access
          channel       = Channel.find_by(id: payload[:channel_id])
          return I18n.t("pito.slash.disconnect.errors.already_gone") if channel.nil?

          handle        = channel.handle.presence || channel.title.to_s
          video_count   = channel.videos.count
          connection_id = channel.youtube_connection_id

          ActiveRecord::Base.transaction do
            channel.destroy!
            if connection_id && !Channel.exists?(youtube_connection_id: connection_id)
              YoutubeConnection.find_by(id: connection_id)&.destroy
            end
          end

          I18n.t("pito.slash.disconnect.confirmation.confirmed",
                 handle: handle, count: video_count)
        end
      end
    end
  end
end
