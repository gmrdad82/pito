# frozen_string_literal: true

module Pito
  module Video
    # Renders a visit-redirect message for a video, in one of two states:
    #
    #   :visiting (default) — a shimmer copy span ("Visiting <title>…") + a hidden
    #     anchor. The pito--auto-visit Stimulus controller auto-clicks the anchor
    #     ONCE after a short delay (opening the video's YouTube page in a new
    #     tab), removes the shimmer, then POSTs to the consume endpoint so the
    #     event is persisted in its :visited state. It never auto-clicks again.
    #
    #   :visited — the consumed, follow-up state: a plain past-tense line
    #     ("Visited <title>.") + a manual [view] link to re-open. No shimmer, no
    #     controller, no auto-click. This is what renders on every page refresh
    #     after the first visit, so the link is never re-clicked automatically.
    #
    # NAMESPACE GOTCHA: inside Pito::Video::*, the bareword `Video` resolves to
    # the Pito::Video MODULE. Use the fully-qualified ::Video constant to
    # reference the model — or simply receive the record as a param (done here).
    #
    # Usage:
    #   render(Pito::Video::VisitComponent.new(video: video))
    #   render(Pito::Video::VisitComponent.new(video: video, state: :visited))
    class VisitComponent < ViewComponent::Base
      STATES       = %i[visiting visited].freeze
      DESTINATIONS = %i[youtube studio].freeze

      def initialize(video:, state: :visiting, destination: :youtube)
        @video       = video
        @state       = STATES.include?(state.to_sym) ? state.to_sym : :visiting
        @destination = DESTINATIONS.include?(destination.to_sym) ? destination.to_sym : :youtube
        @unique_id   = "video-visit-#{video.id}-#{SecureRandom.hex(4)}"
      end

      attr_reader :video, :state, :destination, :unique_id

      def visited?
        state == :visited
      end

      def studio?
        destination == :studio
      end

      # Returns the URL to open based on the destination:
      #   :youtube → the video's YouTube watch page
      #   :studio  → YouTube Studio's edit page for the video
      def target_url
        studio? ? video.youtube_studio_url : video.youtube_video_url
      end

      def copy_text
        if studio?
          key = visited? ? "pito.copy.videos.visited_studio" : "pito.copy.videos.visiting_studio"
        else
          key = visited? ? "pito.copy.videos.visited" : "pito.copy.videos.visiting"
        end
        Pito::Copy.render(key, title: video.title)
      end
    end
  end
end
