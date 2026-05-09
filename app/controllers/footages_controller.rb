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
  # Phase 7.5 §06 — Footage thumbnails. The three frame-streaming
  # endpoints (manifest JSON, master JPEG, thumb JPEG) are public-read.
  # The CLI's wire-shape contract — anchored by
  # `extras/cli/tests/thumbnails_integration.rs` — sends NO
  # `Authorization` header on these GETs. Skipping `authenticate_session!`
  # keeps the scrub UI accessible to terminal clients without a cookie
  # session (the same pattern Active Storage's `disk_service` uses for
  # signed-blob downloads). Theta-phase multi-tenant work will need to
  # tighten this by tenant scoping. The other footage actions (show,
  # edit, update, destroy) keep the cookie-session gate.
  allow_anonymous :frames, :frame_master, :frame_thumb

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
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    project = @footage.project
    @footage.destroy!
    redirect_to project_path(project), notice: "footage deleted."
  end

  # Phase 7.5 §06 — Frame manifest JSON.
  #
  # Returns `{ "duration_seconds": <float>, "timestamps": [<u64>, ...] }`.
  # The `timestamps` array is the on-disk inventory of master frames for
  # this footage, derived from `<assets>/footage_thumbs/<id>/m/`. Empty
  # array is valid — it means "no frames extracted yet" and the scrub UI
  # renders a placeholder. 404 when the footage row itself is missing.
  #
  # Wire-shape anchored by
  # `extras/cli/tests/thumbnails_integration.rs::fetch_manifest_decodes_canonical_response`.
  def frames
    footage = lookup_footage(params[:id])
    timestamps = list_frame_timestamps(footage, :m)
    render json: {
      duration_seconds: footage.duration_seconds.to_f,
      timestamps: timestamps
    }
  end

  # Phase 7.5 §06 — Single master JPEG (1280x720). Streams from
  # `<assets>/footage_thumbs/<id>/m/<HH-MM-SS>.jpg`. 404 when the file is
  # absent OR the timestamp is malformed (defense-in-depth — the route
  # constraint already rejects malformed timestamps but we re-check).
  def frame_master
    serve_frame(:m)
  end

  # Phase 7.5 §06 — Single thumbnail JPEG (320x180). Same path shape as
  # `frame_master` but under the `t/` tier.
  def frame_thumb
    serve_frame(:t)
  end

  private

  def set_footage
    @footage = Footage.find(params[:id])
  end

  # Phase 7.5 §06 — Public-read frame endpoints have no cookie session,
  # so `Current.tenant` is unset and `BelongsToTenant`'s default scope
  # would raise `TenantContextMissing` on a regular `.find`. Single-
  # tenant assumption: every footage row belongs to the seeded tenant.
  # `Footage.unscoped.find` bypasses the default scope. Theta-phase
  # multi-tenant work will need to derive the tenant from the URL or
  # require a session here. `ActiveRecord::RecordNotFound` is rescued
  # by `ApplicationController#render_not_found`.
  def lookup_footage(id)
    Footage.unscoped.find(id)
  end

  # Phase 7.5 §06 — Stream a single frame from the assets root. `tier` is
  # `:m` (master) or `:t` (thumb). Path-traversal defense is layered:
  #
  #   1. Route constraint forces `:filename` to match `\d{2}-\d{2}-\d{2}`.
  #   2. This action re-checks the regex (so a code path that bypasses
  #      the router — direct call from a future internal helper —
  #      still rejects garbage).
  #   3. `Pito::AssetsRoot.path` runs cleanpath + containment so any
  #      `..` segment that survived the regex would still be rejected
  #      with `Pito::AssetsRoot::Error` (handled by 404 below).
  def serve_frame(tier)
    footage = lookup_footage(params[:footage_id])
    filename = params[:filename].to_s
    return head :not_found unless filename.match?(/\A\d{2}-\d{2}-\d{2}\z/)

    path = Pito::AssetsRoot.path(
      "footage_thumbs",
      footage.id.to_s,
      tier.to_s,
      "#{filename}.jpg"
    )
    return head :not_found unless File.exist?(path)

    send_file path.to_s, type: "image/jpeg", disposition: "inline"
  rescue Pito::AssetsRoot::Error
    # Belt-and-suspenders: if the cleanpath containment ever fails (e.g.,
    # a future regex tweak loosens the constraint), surface as 404 rather
    # than a 500.
    head :not_found
  end

  # Phase 7.5 §06 — List the on-disk timestamps for a footage's frame
  # tier as ascending integer seconds. Returns `[]` when the directory
  # doesn't exist (e.g., extraction hasn't run yet).
  def list_frame_timestamps(footage, tier)
    dir = Pito::AssetsRoot.path("footage_thumbs", footage.id.to_s, tier.to_s)
    return [] unless File.directory?(dir)

    Dir.children(dir).filter_map do |name|
      m = name.match(/\A(\d{2})-(\d{2})-(\d{2})\.jpg\z/)
      next unless m
      m[1].to_i * 3600 + m[2].to_i * 60 + m[3].to_i
    end.sort
  rescue Pito::AssetsRoot::Error
    []
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
