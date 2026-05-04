# Phase 4 §3.4, §6, §7.5 — Footage HTML + JSON controller.
#
# Web UI edits only the fields the importer can't fill (§3.4 lifecycle):
#   `kind`, `source`, `game_id`, `platform`, `description`, `nas_path`,
#   `recorded_at`. Probed metadata (resolution, fps, codec, bit_depth,
#   color_profile, etc.) flows from the `pito footage` importer via the
#   nested JSON API at `/api/projects/:project_id/footages` (Add) and the
#   members of this controller in JSON form for Change/Delete (§7.5).
#
# JSON request booleans use the project-wide `"yes"`/`"no"` convention at the
# boundary (CLAUDE.md hard rule); the controller coerces via
# `FootagesParams.coerce_yes_no_attrs`.
class FootagesController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :set_footage, only: [ :show, :edit, :update, :destroy ]

  def index
    # Top-level list — handy for admin / debugging. Notes-style pane lives on
    # the project show page (§9.1). Routing helper kept for the Phase A spec.
    @footages = Footage.order(created_at: :desc).limit(200)
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: footage_json(@footage) }
    end
  end

  def edit
    @games = Game.where(tenant_id: @footage.tenant_id).order(:title)
  end

  def update
    attrs, error = build_update_attrs
    if error
      render json: { error: error }, status: :unprocessable_entity
      return
    end

    if @footage.update(attrs)
      respond_to do |format|
        format.html { redirect_to project_path(@footage.project), notice: "footage updated." }
        format.json { render json: footage_json(@footage) }
      end
    else
      respond_to do |format|
        format.html do
          @games = Game.where(tenant_id: @footage.tenant_id).order(:title)
          render :edit, status: :unprocessable_entity
        end
        format.json { render json: { errors: @footage.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    project = @footage.project
    @footage.destroy!
    respond_to do |format|
      format.html { redirect_to project_path(project), notice: "footage deleted." }
      format.json { head :no_content }
    end
  end

  private

  def set_footage
    @footage = Footage.find(params[:id])
  end

  # Build the update attribute hash. JSON requests pass `has_commentary_track`
  # as "yes"/"no"; HTML form path doesn't include the column. Returns
  # [attrs, error] — error nil on success.
  def build_update_attrs
    permitted =
      if request.format.json?
        params.require(:footage).permit(
          :kind, :source, :game_id, :platform,
          :description, :nas_path, :recorded_at,
          :resolution, :fps, :duration_seconds,
          :codec, :bit_depth, :color_profile,
          :aspect_ratio, :orientation,
          :audio_track_count, :has_commentary_track,
          :filename, :local_path
        )
      else
        params.require(:footage).permit(
          :kind, :source, :game_id, :platform,
          :description, :nas_path, :recorded_at
        )
      end

    if permitted.key?(:has_commentary_track)
      raw = permitted[:has_commentary_track]
      unless YesNo.yes_no?(raw)
        return [ nil, "has_commentary_track must be 'yes' or 'no'" ]
      end
      permitted[:has_commentary_track] = YesNo.from_yes_no(raw)
    end

    [ permitted, nil ]
  end

  def footage_json(footage)
    {
      id: footage.id,
      project_id: footage.project_id,
      tenant_id: footage.tenant_id,
      game_id: footage.game_id,
      kind: footage.kind,
      source: footage.source,
      platform: footage.platform,
      local_path: footage.local_path,
      nas_path: footage.nas_path,
      filename: footage.filename,
      description: footage.description,
      recorded_at: footage.recorded_at&.iso8601,
      duration_seconds: footage.duration_seconds,
      resolution: footage.resolution,
      fps: footage.fps&.to_s,
      codec: footage.codec,
      bit_depth: footage.bit_depth,
      color_profile: footage.color_profile,
      aspect_ratio: footage.aspect_ratio,
      orientation: footage.orientation,
      audio_track_count: footage.audio_track_count,
      has_commentary_track: YesNo.to_yes_no(footage.has_commentary_track)
    }
  end
end
