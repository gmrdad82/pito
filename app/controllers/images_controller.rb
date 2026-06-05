# frozen_string_literal: true

# Image pipeline endpoints. Returns JSON with cover art / thumbnail URLs.
#
# Game cover art is served via ActiveStorage (game.cover_art attachment).
# Video thumbnails return the YouTube-supplied thumbnail_url directly.
class ImagesController < ApplicationController
  allow_anonymous :show_game

  # GET /images/games/:id.json
  def show_game
    game = Game.find(params[:id])
    cover_url = game.cover_art.attached? ? url_for(game.cover_art) : nil

    render json: {
      id:        game.id,
      title:     game.title,
      cover_url: cover_url,
      has_cover: cover_url.present?
    }
  end

  # GET /images/videos/:id/thumbnail.json
  def show_video_thumbnail
    video = Video.find(params[:id])
    render json: {
      id:               video.id,
      youtube_video_id: video.youtube_video_id,
      thumbnail_url:    video.thumbnail_url
    }
  end
end
