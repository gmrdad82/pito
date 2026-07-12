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
      if q.blank?
        # Clearing the search restores page 1 AND the pager sentinel — a
        # bare rows render here used to strand the picker capped at 50.
        videos, next_cursor = Video.picker_page
        render partial: "videos/picker_reset", locals: { videos:, next_cursor: }
      else
        videos = Video.includes(:channel).where("title ILIKE ?", "%#{q}%").order(:title).limit(50)
        render partial: "videos/picker_rows", locals: { videos: videos }
      end
    end
  end
end
