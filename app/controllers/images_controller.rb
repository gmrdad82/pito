# Image pipeline endpoints. Returns JSON with cover art / thumbnail URLs
# and metadata for games and videos.
#
# Game cover art is served from the local filesystem via the
# `public/covers/` symlink (resolves to `<PITO_ASSETS_PATH>/covers/`).
# The controller checks disk presence and returns the URL + has_cover
# flag so clients can render or fall back gracefully.
#
# Video thumbnails return the YouTube-supplied thumbnail_url directly;
# no local file check is performed (the URL is an external CDN link).
class ImagesController < ApplicationController
  allow_anonymous :show_game

  # GET /images/games/:id.json
  def show_game
    game = Game.find(params[:id])
    cover_path = Pito::AssetsRoot.path("covers", "games", game.id.to_s, "master.jpg")
    has_cover = File.exist?(cover_path)

    render json: {
      id: game.id,
      title: game.title,
      cover_url: has_cover ? "/covers/games/#{game.id}/master.jpg" : nil,
      has_cover: has_cover
    }
  end

  # GET /images/videos/:id/thumbnail.json
  def show_video_thumbnail
    video = Video.find(params[:id])
    render json: {
      id: video.id,
      youtube_video_id: video.youtube_video_id,
      thumbnail_url: video.thumbnail_url
    }
  end
end
