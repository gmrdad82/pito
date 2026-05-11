# Phase 22 §5 — Imports::ChannelsController.
#
# Drives the `[import]` modal on `/videos`. Four actions:
#
#   index  — modal frame, channel selection step.
#   create — per-selected-channel enqueue with rate-limit + re-enqueue
#            refusal (locked decision #1).
#   show   — per-ImportJob progress / keep-reject view.
#   update — apply keep / reject decisions; destroys non-kept Videos
#            and inserts RejectedVideoImport tombstones in one tx.
#
# Auth is the standard cookie-session gate via the inherited
# `Sessions::AuthConcern`. Every external boolean is `"yes"` / `"no"`.
class Imports::ChannelsController < ApplicationController
  # 5-second per-user lock on the enqueue endpoint; second click in
  # under 5s returns 429.
  ENQUEUE_RATE_LIMIT_TTL = 5.seconds

  # 2026-05-11 fix — Action Cable subscription grace window.
  #
  # The progress modal uses `turbo_stream_from "import_jobs"` to receive
  # `broadcast_replace_to` updates from `Channel::ImportVideosJob`. The
  # cable subscription is established AFTER the page renders and the
  # browser parses the `<turbo-stream-source>` element. If a Sidekiq
  # worker picks the job up and finishes (broadcast included) before the
  # browser has finished the subscription handshake, that broadcast is
  # dropped on the floor and the row stays at its server-rendered
  # `queued` state forever.
  #
  # The dev log captured exactly this for the "Witty Gaming" channel on
  # 2026-05-11: the worker emitted both the `running` and `completed`
  # broadcasts ~70ms after enqueue, ~150ms before the browser subscribed
  # to `import_jobs`. The user-visible symptom is the row reading
  # `queued` after every other channel in the same batch (which the
  # subscription caught) has flipped to `no new uploads`.
  #
  # The previous `@enqueued.each(&:reload)` defense (commit `e09bf23`)
  # closes a different race window (worker finishes between create and
  # render): it reloads the DB once before render. It does NOT help when
  # the broadcast itself races the subscription handshake — the reload
  # happens too early to capture the worker's state, and the broadcast
  # arrives too early for the browser to receive it.
  #
  # Smallest viable fix: enqueue with `perform_in(SUBSCRIPTION_GRACE, …)`
  # instead of `perform_async`. The worker still runs (same Sidekiq
  # queue, same retry semantics, same `perform` body), it just starts
  # one second later. By then, both the server-render path and the
  # cable subscription handshake have completed, so the worker's first
  # broadcast lands on a live subscription.
  SUBSCRIPTION_GRACE = 1.second

  # JSON-friendly: skip CSRF only for JSON request bodies. HTML keeps
  # its authenticity token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  def index
    @channels = Channel.connected.order(:channel_url)

    respond_to do |format|
      format.html
      format.json { render :index, formats: :json }
    end
  end

  def create
    if rate_limited?
      respond_rate_limited
      return
    end

    requested_ids = parse_channel_ids
    if requested_ids.empty?
      respond_with_errors([ "select at least one channel" ], :unprocessable_content)
      return
    end

    @enqueued = []
    @errors   = []

    requested_ids.each do |raw_id|
      channel = resolve_channel(raw_id)
      if channel.nil?
        @errors << "channel not found: #{raw_id}"
        next
      end

      if channel.in_flight_import?
        @errors << "import already running for channel #{channel.id}"
        next
      end

      job = ImportJob.create!(
        channel: channel,
        enqueued_by: Current.user,
        status: :queued
      )
      # `perform_in` (not `perform_async`) — see SUBSCRIPTION_GRACE
      # docstring above for the cable-subscription race this avoids.
      Channel::ImportVideosJob.perform_in(SUBSCRIPTION_GRACE, channel.id, job.id)
      @enqueued << job
    end

    if @enqueued.empty?
      respond_with_errors(@errors, :unprocessable_content)
      return
    end

    # Re-fetch each ImportJob right before rendering so the modal
    # reflects the latest persisted state. With `Sidekiq` running, fast
    # workers can flip `queued -> completed` between `perform_async` and
    # the controller rendering the view; without this reload, the
    # modal would server-render `queued` forever for jobs that already
    # finished, because the Turbo Stream broadcast fired before the
    # browser subscribed to `import_jobs`.
    @enqueued.each(&:reload)

    respond_to do |format|
      format.html do
        # Render the progress step in place of the modal body.
        render :create
      end
      format.json do
        render :create, formats: :json,
                        status: @errors.any? ? :multi_status : :created
      end
    end
  end

  def show
    @import_job = ImportJob.find(params[:id])
    @channel = @import_job.channel
    @candidate_videos = @import_job.completed? ? @import_job.candidate_videos.to_a : []

    respond_to do |format|
      format.html
      format.json { render :show, formats: :json }
    end
  end

  def update
    @import_job = ImportJob.find(params[:id])
    @channel = @import_job.channel

    unless @import_job.completed?
      respond_with_errors([ "import is not complete yet" ], :unprocessable_content)
      return
    end

    keep_ids = parse_keep_ids
    candidates = @import_job.candidate_videos.to_a
    kept_ids = candidates.select { |v| keep_ids.include?(v.id) }.map(&:id)
    rejected_videos = candidates.reject { |v| keep_ids.include?(v.id) }

    @kept = kept_ids.size
    @rejected = 0

    ImportJob.transaction do
      rejected_videos.each do |video|
        # Tombstone before destroy so the unique index protects against
        # races. `find_or_create_by!` ensures repeated submits don't
        # 500 on the unique violation.
        RejectedVideoImport.find_or_create_by!(
          channel: @channel,
          youtube_video_id: video.youtube_video_id
        ) do |row|
          row.rejected_at = Time.current
          row.rejected_by = Current.user
        end
        video.destroy!
        @rejected += 1
      end
    end

    respond_to do |format|
      format.html do
        flash[:notice] = "kept #{@kept}, rejected #{@rejected}."
        redirect_to videos_path
      end
      format.json { render :update, formats: :json }
    end
  end

  private

  # Per-user 5-second cache lock. `unless_exist: true` is atomic on the
  # Redis cache store and on the test in-memory store.
  def rate_limited?
    return false unless Current.user

    lock_key = "imports:enqueue:user:#{Current.user.id}"
    !Rails.cache.write(lock_key, 1, expires_in: ENQUEUE_RATE_LIMIT_TTL, unless_exist: true)
  end

  def respond_rate_limited
    respond_to do |format|
      format.html do
        redirect_to videos_path, alert: "try again in a moment."
      end
      format.json do
        render json: { error: "rate_limited", retry_after_seconds: ENQUEUE_RATE_LIMIT_TTL.to_i },
               status: :too_many_requests
      end
    end
  end

  def respond_with_errors(messages, status)
    respond_to do |format|
      format.html do
        redirect_to imports_channels_path, alert: messages.first
      end
      format.json do
        render json: { errors: messages }, status: status
      end
    end
  end

  def parse_channel_ids
    raw = params[:channel_ids]
    return [] if raw.blank?

    Array(raw).flat_map { |v| v.to_s.split(/[\s,]+/) }.reject(&:blank?)
  end

  def parse_keep_ids
    raw = params[:keep_video_ids]
    return [] if raw.blank?

    Array(raw).flat_map { |v| v.to_s.split(/[\s,]+/) }.reject(&:blank?).map(&:to_i)
  end

  def resolve_channel(raw_id)
    Channel.friendly.find(raw_id)
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
