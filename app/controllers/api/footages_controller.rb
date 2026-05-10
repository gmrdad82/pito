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
    # Phase 12 — Step A. The cookie-session before_action defaults to
    # redirecting unauthenticated callers to /login. JSON / API surfaces
    # bypass that redirect entirely — `Api::AuthConcern` (below) handles
    # bearer-token auth and returns a 401 JSON envelope.
    skip_before_action :authenticate_session!
    # CSRF protection is irrelevant for bearer-only JSON endpoints.
    skip_before_action :verify_authenticity_token, raise: false

    # Phase 3 — Step B. Bearer-token auth is required on every Api::*
    # endpoint. The concern populates Current.user / Current.token from
    # the resolved token; the cookie-only HTML routes do NOT include this
    # concern.
    include Api::AuthConcern

    before_action :set_project, only: [ :index, :create ]
    before_action :set_footage, only: [ :update, :destroy, :update_frames ]

    def index
      require_scope!(Scopes::PROJECT_READ)
      footages = @project.footages.order(:local_path)
      render json: footages.map { |f| footage_json(f) }
    end

    def create
      require_scope!(Scopes::PROJECT_WRITE)

      attrs, error = build_create_attrs
      if error
        render json: { error: error }, status: :unprocessable_content
        return
      end

      footage = @project.footages.new(attrs)
      if footage.save
        render json: footage_json(footage), status: :created
      else
        render json: { errors: footage.errors.full_messages }, status: :unprocessable_content
      end
    end

    def update
      require_scope!(Scopes::PROJECT_WRITE)

      attrs, error = build_update_attrs
      if error
        render json: { error: error }, status: :unprocessable_content
        return
      end

      if @footage.update(attrs)
        render json: footage_json(@footage)
      else
        render json: { errors: @footage.errors.full_messages }, status: :unprocessable_content
      end
    end

    def destroy
      require_scope!(Scopes::PROJECT_WRITE)

      @footage.destroy!
      head :no_content
    end

    # Phase 7.5 §06 — Bulk frame upload from the importer.
    #
    # The importer extracts the full frame set per footage (master 1280x720
    # + thumb 320x180, letterboxed to 16:9) and PATCHes them here. Body
    # shape (multipart):
    #
    #   frames[<HH-MM-SS>][master] => <JPEG file part>
    #   frames[<HH-MM-SS>][thumb]  => <JPEG file part>
    #
    # Each part is written atomically to
    # `<assets>/footage_thumbs/<footage_id>/{m,t}/<HH-MM-SS>.jpg`.
    # Path-traversal defense is layered: the timestamp key must match
    # `HH-MM-SS` (regex check) and `Pito::AssetsRoot.path` re-verifies
    # cleanpath containment before any write.
    #
    # On success: stamps `frames_extracted_at` if any part was written and
    # returns `{ "frames_uploaded": <int>, "footage_id": <int> }`. CLI
    # integration tests do NOT anchor this URL (importer side ships in a
    # later dispatch), so the URL is chosen for `/api/` consistency.
    def update_frames
      require_scope!(Scopes::PROJECT_WRITE)

      uploads = params[:frames]
      uploaded = 0

      if uploads.is_a?(ActionController::Parameters) || uploads.is_a?(Hash)
        uploads.each do |timestamp, files|
          next unless timestamp.to_s.match?(/\A\d{2}-\d{2}-\d{2}\z/)
          next unless files.is_a?(ActionController::Parameters) || files.is_a?(Hash)

          if (master = files[:master]).present? && uploaded_file?(master)
            write_frame(@footage, :m, timestamp.to_s, master)
            uploaded += 1
          end
          if (thumb = files[:thumb]).present? && uploaded_file?(thumb)
            write_frame(@footage, :t, timestamp.to_s, thumb)
            uploaded += 1
          end
        end
      end

      @footage.update!(frames_extracted_at: Time.current) if uploaded.positive?

      render json: { frames_uploaded: uploaded, footage_id: @footage.id }
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

    # Phase 7.5 §06 — Atomic write of an uploaded frame JPEG to its
    # tier+timestamp path. The path resolves through `Pito::AssetsRoot`
    # which enforces cleanpath containment, so a malicious `timestamp`
    # that smuggled `..` through the regex would still be caught here.
    def write_frame(footage, tier, timestamp, uploaded_file)
      dir = Pito::AssetsRoot.ensure_dir!("footage_thumbs", footage.id.to_s, tier.to_s)
      target = dir.join("#{timestamp}.jpg")
      tmp = dir.join("#{timestamp}.jpg.tmp")
      File.binwrite(tmp, uploaded_file.read)
      File.rename(tmp, target)
    end

    def uploaded_file?(value)
      value.respond_to?(:read)
    end

    def footage_json(footage)
      {
        id: footage.id,
        project_id: footage.project_id,
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
