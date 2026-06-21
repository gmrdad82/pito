# frozen_string_literal: true

module Videos
  # POST /videos/search-local
  #
  # Searches the local Video table for videos whose title matches the query.
  # Returns HTML row markup for the videos picker sidebar list — the JS swaps
  # the `data-pito--videos-nav-target="list"` container's innerHTML with it.
  #
  # Request params:
  #   q — String; blank returns first 50 videos ordered by title
  #
  # Response:
  #   text/html — .pito-video-row elements (no wrapping container, no layout)
  #
  # Auth: requires authentication (no allow_anonymous declared).
  class SearchLocalController < ApplicationController
    def create
      q = params[:q].to_s.strip
      videos = if q.blank?
        Video.includes(:channel).order(:title).limit(50)
      else
        Video.includes(:channel).where("title ILIKE ?", "%#{q}%").order(:title).limit(50)
      end

      render partial: "videos/picker_rows", locals: { videos: videos }
    end
  end
end
