# frozen_string_literal: true

module Pito
  module Sidebar
    module Videos
      # Renders the video picker list for the sidebar.
      #
      # Displays a flat list of videos (id + title + @handle), keyboard-selectable.
      # The outer container mounts `data-controller="pito--videos-nav"` so the
      # Stimulus controller can attach keyboard navigation and debounced local search.
      #
      # Constructor:
      #   videos — ActiveRecord relation or Array of Video records (responds to
      #            #id, #title, #channel).
      class Component < ViewComponent::Base
        # @param videos [Array<Video>]
        def initialize(videos:)
          @videos = videos
        end

        def empty?
          @videos.empty?
        end

        def empty_state_text
          Pito::Copy.render("pito.copy.videos.picker_empty")
        end

        attr_reader :videos
      end
    end
  end
end
