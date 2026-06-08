# frozen_string_literal: true

module Pito
  module Video
    # Renders a compact list of video rows for `list videos`.
    #
    # Each row shows: title, @channel handle, privacy_status label, and the
    # video id (so the user can `show video <id>`).
    #
    # NAMESPACE GOTCHA: inside Pito::Video::*, the bareword `Video` resolves to
    # the Pito::Video MODULE. Use ::Video (the model) only when needed — here
    # we receive records as params so it doesn't matter.
    class ListComponent < ViewComponent::Base
      def initialize(videos:)
        @videos = videos
      end

      def videos
        @videos
      end

      # Returns the privacy label for a video (public / unlisted / private).
      def privacy_label_for(video)
        return nil if video.privacy_status.blank?

        I18n.t("pito.video.detail.privacy_status.#{video.privacy_status}",
               default: video.privacy_status.to_s.capitalize)
      end
    end
  end
end
