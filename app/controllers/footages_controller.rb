# Phase 4 §3.4, §6, §7.5 — Footage HTML controller.
#
# Web UI edits only the fields the importer can't fill (§3.4 lifecycle):
#   `kind`, `source`, `game_id`, `platform`, `description`, `nas_path`,
#   `recorded_at`. Probed metadata (resolution, fps, codec, bit_depth,
#   color_profile, etc.) flows from the `pito footage` importer via the
#   nested JSON API at `/api/projects/:project_id/footages` (Add) and the
#   member actions in `Api::FootagesController`
#   (`PATCH /api/footages/:id.json` and `DELETE /api/footages/:id.json`).
#
# This controller serves:
#   - HTML index / show / edit / update / destroy (web UI flows).
#   - GET /footages/:id.json (read-only, used by inline edit / show paths and
#     Stimulus consumers). The yes/no convention applies to the response
#     body; consumers parse `fps` as a JSON number.
#
# JSON write paths (PATCH / DELETE) live under `Api::FootagesController` for
# surface symmetry with collection actions.
class FootagesController < ApplicationController
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
    permitted = params.require(:footage).permit(
      :kind, :source, :game_id, :platform,
      :description, :nas_path, :recorded_at
    )

    if @footage.update(permitted)
      redirect_to project_path(@footage.project), notice: "footage updated."
    else
      @games = Game.where(tenant_id: @footage.tenant_id).order(:title)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    project = @footage.project
    @footage.destroy!
    redirect_to project_path(project), notice: "footage deleted."
  end

  private

  def set_footage
    @footage = Footage.find(params[:id])
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
      fps: footage.fps&.to_f,
      codec: footage.codec,
      bit_depth: footage.bit_depth,
      color_profile: footage.color_profile,
      aspect_ratio: footage.aspect_ratio,
      orientation: footage.orientation,
      audio_track_count: footage.audio_track_count,
      has_commentary_track: YesNo.to_yes_no(footage.has_commentary_track),
      filesize_bytes: footage.filesize_bytes
    }
  end
end
