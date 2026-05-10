# Phase 4 §3.6, §11.1 — Timeline controller.
#
# State machine (aasm) on the model: editing → exported → uploaded.
# Transition events on the controller surface as PATCH actions:
#   PATCH /timelines/:id { transition: "export" }
#   PATCH /timelines/:id { transition: "upload", youtube_url: "..." }
#
# `upload!` takes a YouTube URL and creates/links a Video record. The
# scaffold here keeps the wiring minimal — Phase 7's YouTube integration
# will replace the stub Video creation with real API metadata.
class TimelinesController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :set_timeline, only: [ :show, :update, :destroy ]

  def index
    # Top-level list — kept for the Phase A routing helper.
    @timelines = Timeline.order(created_at: :desc).limit(200)
  end

  def show
  end

  def create
    project = Project.friendly.find(params[:project_id])
    timeline = project.timelines.new
    timeline.save!
    redirect_to project_path(project), notice: "timeline created."
  end

  def update
    transition = params[:transition].to_s
    if transition.present?
      apply_transition!(transition)
      return
    end

    if @timeline.update(update_params)
      redirect_to project_path(@timeline.project), notice: "timeline updated."
    else
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    project = @timeline.project
    @timeline.destroy!
    redirect_to project_path(project), notice: "timeline deleted."
  end

  private

  def set_timeline
    @timeline = Timeline.find(params[:id])
  end

  def update_params
    params.require(:timeline).permit(:title, :duration_seconds, :resolution, :fps, :export_filename)
  end

  def apply_transition!(transition)
    case transition
    when "export"
      if @timeline.may_export?
        @timeline.export!
        redirect_to project_path(@timeline.project), notice: "timeline exported."
      else
        redirect_to project_path(@timeline.project),
                    alert: "cannot export from #{@timeline.state} state."
      end
    when "upload"
      if @timeline.may_upload?
        link_or_create_video_for_upload(params[:youtube_url].to_s)
        @timeline.upload!
        redirect_to project_path(@timeline.project), notice: "timeline uploaded."
      else
        redirect_to project_path(@timeline.project),
                    alert: "cannot upload from #{@timeline.state} state."
      end
    else
      redirect_to project_path(@timeline.project),
                  alert: "unknown transition: #{transition}"
    end
  end

  # Phase 7 Path A2 (literal full retract). When `upload!` fires, the
  # caller passes a YouTube URL and the transition creates or links a
  # Video. Video is now a thin YouTube-reference record (no title/
  # description/etc.); we just stamp the youtube_video_id on the row.
  # Phase 8+ will populate metadata when real YouTube sync ships.
  def link_or_create_video_for_upload(youtube_url)
    return if youtube_url.blank?

    youtube_id = extract_youtube_id(youtube_url)
    return if youtube_id.blank?

    video = Video.find_or_initialize_by(youtube_video_id: youtube_id)
    if video.new_record?
      video.channel ||= Channel.first
      return unless video.channel # nothing to attach to yet
      video.save!
    end
    @timeline.video = video
    @timeline.save!
  end

  def extract_youtube_id(url)
    return nil if url.blank?
    match = url.match(/(?:youtu\.be\/|v=|\/shorts\/)([\w-]{11})/)
    match&.captures&.first
  end
end
