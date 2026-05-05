# Phase 4 §7.5 — JSON API for the `pito footage` importer.
#
# Routes:
#   GET  /api/projects/:project_id/footages   — index, used for diff (§7.3)
#   POST /api/projects/:project_id/footages   — create (importer "Add" branch)
#
# Booleans serialize as "yes"/"no" per the project-wide rule (CLAUDE.md).
# Update / Delete use the top-level FootagesController with JSON format.
module Api
  class FootagesController < ApplicationController
    skip_before_action :verify_authenticity_token

    before_action :set_project

    def index
      footages = @project.footages.order(:local_path)
      render json: footages.map { |f| footage_json(f) }
    end

    def create
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

    private

    def set_project
      @project = Project.find(params[:project_id])
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
