# Phase 14 §3 — Video↔Game link CRUD.
#
# Surface (nested under `/videos/:video_id/links`):
#
#   POST   /videos/:video_id/links            create a new link
#   PATCH  /videos/:video_id/links/:id        flip is_primary
#   DELETE /videos/:video_id/links/:id        remove the link
#
# Boundary discipline (CLAUDE.md):
#   - `is_primary` arrives as `"yes"` / `"no"` strings on the wire.
#   - Duplicate (same video + same game) is rejected (422). Master-
#     agent decision #7: surface the uniqueness 422 as a clean flash
#     ("already linked").
#
# Permissions: anyone signed in can add or remove any link, regardless
# of who created it (master-agent decision #8 / ADR 0003).
#
# R1 (2026-05-25) — bundle link type removed. Only `game` links remain.
class VideoGameLinksController < ApplicationController
  before_action :load_video

  def create
    link_type = params[:link_type].to_s
    linked_id = params[:linked_id].to_i
    is_primary_param = params[:is_primary]

    unless YesNo.yes_no?(is_primary_param) || is_primary_param.nil?
      return render_unprocessable("is_primary must be 'yes' or 'no'.")
    end

    is_primary = is_primary_param.present? && YesNo.from_yes_no(is_primary_param)

    case link_type
    when "game"
      return render_unprocessable("linked_id is required.") unless linked_id.positive?
      return render_unprocessable("game not found.") unless Game.exists?(linked_id)

      link = @video.video_game_links.new(
        link_type: :game,
        game_id: linked_id,
        is_primary: is_primary
      )
    else
      return render_unprocessable("link_type must be 'game'.")
    end

    if link.save
      redirect_to edit_video_path(@video), notice: "link added."
    else
      message = uniqueness_violation?(link) ? "already linked." : link.errors.full_messages.join(", ")
      render_unprocessable(message)
    end
  rescue ActiveRecord::RecordNotUnique
    render_unprocessable("already linked.")
  end

  def update
    link = @video.video_game_links.find(params[:id])

    flip = params[:is_primary]
    return render_unprocessable("is_primary must be 'yes' or 'no'.") unless YesNo.yes_no?(flip)

    if link.update(is_primary: YesNo.from_yes_no(flip))
      redirect_to edit_video_path(@video), notice: "link updated."
    else
      render_unprocessable(link.errors.full_messages.join(", "))
    end
  end

  def destroy
    link = @video.video_game_links.find(params[:id])
    link.destroy!
    redirect_to edit_video_path(@video), notice: "link removed."
  end

  private

  def load_video
    @video = Video.friendly.find(params[:video_id])
  end

  def uniqueness_violation?(link)
    link.errors.details.values.flatten.any? { |d| d[:error] == :taken }
  end

  def render_unprocessable(message)
    redirect_to edit_video_path(@video), alert: message,
                status: :see_other
  end
end
