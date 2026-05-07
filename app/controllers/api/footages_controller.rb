# Phase 4 §7.5 — JSON API for the `pito footage` importer.
#
# Routes (all under `/api/` for surface symmetry — Phase 5.5 cleanup):
#   GET    /api/projects/:project_id/footages.json — index, used for diff (§7.3)
#   POST   /api/projects/:project_id/footages.json — create ("Add" branch)
#   PATCH  /api/footages/:id.json                  — update probed metadata
#   DELETE /api/footages/:id.json                  — remove a missing file
#
# The HTML edit / destroy flow stays at top-level
# `/footages/:id` (no `.json`) and is served by `FootagesController`.
#
# Booleans serialize as "yes"/"no" per the project-wide rule (CLAUDE.md).
module Api
  class FootagesController < ApplicationController
    skip_before_action :verify_authenticity_token

    # Phase 3 — Step B. Bearer-token auth is required on every Api::*
    # endpoint. The concern populates Current.tenant / Current.user from
    # the resolved token; the cookie-only HTML routes do NOT include this
    # concern (they remain on the seeded-singletons path).
    include Api::AuthConcern

    # Skip the cookie-based set_current_tenant_and_user before_action —
    # the auth concern populates Current from the resolved token instead.
    skip_before_action :set_current_tenant_and_user

    before_action :set_project, only: [ :index, :create ]
    before_action :set_footage, only: [ :update, :destroy ]

    def index
      require_scope!(Scopes::PROJECT_READ)
      footages = @project.footages.order(:local_path)
      render json: footages.map { |f| footage_json(f) }
    end

    def create
      require_scope!(Scopes::PROJECT_WRITE)

      attrs, error = build_create_attrs
      if error
        render json: { error: error }, status: :unprocessable_entity
        return
      end

      footage = @project.footages.new(attrs.merge(tenant: @project.tenant))
      if footage.save
        render json: footage_json(footage), status: :created
      else
        render json: { errors: footage.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      require_scope!(Scopes::PROJECT_WRITE)

      attrs, error = build_update_attrs
      if error
        render json: { error: error }, status: :unprocessable_entity
        return
      end

      if @footage.update(attrs)
        render json: footage_json(@footage)
      else
        render json: { errors: @footage.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      require_scope!(Scopes::PROJECT_WRITE)

      @footage.destroy!
      head :no_content
    end

    private

    def set_project
      @project = Project.find(params[:project_id])
    end

    def set_footage
      @footage = Footage.find(params[:id])
    end

    def build_create_attrs
      permitted = params.require(:footage).permit(
        :kind, :source, :game_id, :platform,
        :description, :nas_path, :recorded_at,
        :local_path, :filename, :filesize_bytes,
        :resolution, :fps, :duration_seconds,
        :codec, :bit_depth, :color_profile,
        :aspect_ratio, :orientation,
        :audio_track_count, :has_commentary_track
      )

      coerce_yes_no_attrs(permitted)
    end

    def build_update_attrs
      permitted = params.require(:footage).permit(
        :kind, :source, :game_id, :platform,
        :description, :nas_path, :recorded_at,
        :resolution, :fps, :duration_seconds,
        :codec, :bit_depth, :color_profile,
        :aspect_ratio, :orientation,
        :audio_track_count, :has_commentary_track,
        :filename, :local_path, :filesize_bytes
      )

      coerce_yes_no_attrs(permitted)
    end

    # Validate and convert the `has_commentary_track` yes/no string into a
    # Boolean. Returns [attrs, error] — error nil on success.
    def coerce_yes_no_attrs(permitted)
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
end
