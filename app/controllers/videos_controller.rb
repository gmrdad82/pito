class VideosController < ApplicationController
  include FriendlyRedirect
  include ScheduledPublishHelper

  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON requests so the HTML form path keeps
  # its authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # Phase 12 — re-introduce sortable columns dropped during Path A2.
  ALLOWED_SORTS = {
    "id" => "videos.id",
    "title" => "videos.title",
    "created_at" => "videos.created_at",
    "updated_at" => "videos.updated_at",
    "last_synced_at" => "videos.last_synced_at",
    "published_at" => "videos.published_at",
    "privacy_status" => "videos.privacy_status",
    "starred" => "videos.star"
  }.freeze
  ALLOWED_DIRS = %w[asc desc].freeze
  DEFAULT_SORT = "created_at"
  DEFAULT_DIR = "desc"

  PRIVACY_VALUES_FOR_PUBLISH = %w[public unlisted].freeze

  before_action :load_video, only: %i[
    show edit update destroy stats
    pre_publish_checklist publish schedule unpublish
    diff apply_diff
  ]

  def index
    @saved_views = SavedView.videos.ordered

    # Phase 21 — `?channel=<slug-or-id>` filter chip on the videos
    # picker. Resolution mirrors ChannelsController#show (slug-or-id
    # via `Channel.friendly.find`). Unknown channel = 404 so the
    # filter chip can't silently render an empty table for a typo'd
    # slug. `@filter_channel` is exposed to the view so the active
    # chip can label itself with the channel's title (falling back
    # to the slug).
    @filter_channel = nil
    if params[:channel].present?
      @filter_channel = Channel.friendly.find(params[:channel])
    end

    scope = Video.includes(:channel)
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        # CAST AS BIGINT is Postgres-portable. MySQL used SIGNED; replaced during Phase 2.
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
      )
      .group("videos.id")
    scope = scope.where(channel_id: @filter_channel.id) if @filter_channel
    @videos = scope.order(sort_clause)
    @sort = sanitized_sort_key
    @dir = sanitized_dir
    @max_panes = max_panes

    respond_to do |format|
      format.html
      format.json { render json: @videos.map { |v| VideoDecorator.new(v).as_summary_json } }
    end
  end

  def show
    return if redirect_to_canonical_slug!(@video) { |v| video_path(v) }

    @max_panes = max_panes
    @available_videos = Video.where.not(id: @video.id).order(created_at: :desc).limit(50)

    respond_to do |format|
      format.html
      format.json { render json: VideoDecorator.new(@video).as_detail_json }
    end
  end

  def edit
    load_edit_form_locals
    # Phase 11 §01a — eager-load + ensure at least one form row each
    # for chapters + end-screens so the nested editor always renders
    # a starting slot.
    @video_chapters = @video.video_chapters.order(:start_seconds).to_a
    @video_end_screens = @video.video_end_screens.order(:position, :id).to_a
  end

  def update
    if smuggled_publish_state?
      return render_smuggle_error
    end

    # Form sends `tags_csv` as a comma-separated string; translate
    # before VideoPolicy.permit so the writable subset stays declared
    # in one place.
    raw_video_params = params.fetch(:video, {}).to_unsafe_h.with_indifferent_access
    if raw_video_params.key?(:tags_csv)
      csv = raw_video_params.delete(:tags_csv).to_s
      tags = csv.split(",").map(&:strip).reject(&:blank?)
      raw_video_params[:tags] = tags
    end

    # Phase 11 §01a — End-screen `kind: none` collapse. When the
    # form submits a `kind: "none"` row (or any row that resolves to
    # `none`), every OTHER end-screen row gets marked `_destroy: 1`
    # before save so the model invariant "no mixing none with other
    # kinds" holds. The collapse runs server-side because the form
    # cannot reliably destroy rows the user did not interact with.
    collapse_end_screens_if_none!(raw_video_params)

    # Phase 11 §01a — yes/no boundary RESERVED GUARD. The current
    # writable subset has no Boolean fields exposed as `yes`/`no` at
    # the wire (`self_declared_made_for_kids` and
    # `contains_synthetic_media` ride as `"1"`/`"0"` form checkboxes,
    # legacy contract). If a future writable Boolean lands, route it
    # through `YesNo.from_yes_no` here before `permit`.

    attrs = VideoPolicy.permit(ActionController::Parameters.new(raw_video_params))

    if @video.update(attrs)
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: "video updated." }
        format.json { render json: VideoDecorator.new(@video.reload).as_detail_json }
      end
    else
      respond_to do |format|
        format.html do
          load_edit_form_locals
          @video_chapters = @video.video_chapters.order(:start_seconds).to_a
          @video_end_screens = @video.video_end_screens.order(:position, :id).to_a
          render :edit, status: :unprocessable_content
        end
        format.json { render json: { errors: @video.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def pre_publish_checklist
    @target_action = params[:target_action].to_s == "schedule" ? "schedule" : "publish"
    render partial: "videos/pre_publish_modal",
           locals: { video: @video, target_action: @target_action }
  end

  def publish
    perms = VideoPolicy.permit_publish(params.fetch(:video, {}))
    error = validate_publish(perms, @video)
    if error
      return render_publish_error(error)
    end

    target = perms[:target_privacy_status].to_s
    @video.assign_attributes(
      pre_publish_game_ok: yes_no_attr(perms[:pre_publish_game_ok]),
      pre_publish_age_ok: yes_no_attr(perms[:pre_publish_age_ok]),
      pre_publish_paid_promotion_ok: yes_no_attr(perms[:pre_publish_paid_promotion_ok]),
      pre_publish_end_screen_ok: yes_no_attr(perms[:pre_publish_end_screen_ok]),
      pre_publish_checked_at: Time.current,
      privacy_status: target.to_sym,
      published_at: @video.published_at || Time.current
    )

    if @video.save
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: "video published." }
        format.json { render json: VideoDecorator.new(@video.reload).as_detail_json }
      end
    else
      render_publish_error(@video.errors.full_messages.join(", "))
    end
  end

  def schedule
    perms = VideoPolicy.permit_schedule(params.fetch(:video, {}))
    error = validate_schedule(perms, @video)
    if error
      return render_publish_error(error, target_action: "schedule")
    end

    @video.assign_attributes(
      pre_publish_game_ok: yes_no_attr(perms[:pre_publish_game_ok]),
      pre_publish_age_ok: yes_no_attr(perms[:pre_publish_age_ok]),
      pre_publish_paid_promotion_ok: yes_no_attr(perms[:pre_publish_paid_promotion_ok]),
      pre_publish_end_screen_ok: yes_no_attr(perms[:pre_publish_end_screen_ok]),
      pre_publish_checked_at: Time.current,
      publish_at: parsed_publish_at(perms[:publish_at]),
      privacy_status: :private
    )

    if @video.save
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: "video scheduled." }
        format.json { render json: VideoDecorator.new(@video.reload).as_detail_json }
      end
    else
      render_publish_error(@video.errors.full_messages.join(", "), target_action: "schedule")
    end
  end

  # Phase 12 — `public` / `unlisted` → `private` (unpublish).
  # Going down is free per Note 1; no checklist needed. Routed
  # separately from `update` so the privacy_status flip lives
  # outside the smuggle guard's blocklist.
  def unpublish
    unless @video.privacy_public? || @video.privacy_unlisted?
      msg = "only public or unlisted videos can be unpublished."
      respond_to do |format|
        format.html do
          load_edit_form_locals
          @video_chapters = @video.video_chapters.order(:start_seconds).to_a
          @video_end_screens = @video.video_end_screens.order(:position, :id).to_a
          @video.errors.add(:base, msg)
          render :edit, status: :unprocessable_content
        end
        format.json { render json: { errors: [ msg ] }, status: :unprocessable_content }
      end
      return
    end

    if @video.update(privacy_status: :private)
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: "video unpublished." }
        format.json { render json: VideoDecorator.new(@video.reload).as_detail_json }
      end
    else
      respond_to do |format|
        format.html do
          load_edit_form_locals
          @video_chapters = @video.video_chapters.order(:start_seconds).to_a
          @video_end_screens = @video.video_end_screens.order(:position, :id).to_a
          render :edit, status: :unprocessable_content
        end
        format.json { render json: { errors: @video.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @video.destroy
    respond_to do |format|
      format.html { redirect_to videos_path, notice: "video deleted." }
      format.json { head :no_content }
    end
  end

  # GET /videos/:id/stats(.json)
  def stats
    @stats = @video.video_stats.order(date: :desc)

    respond_to do |format|
      format.html { redirect_to video_path(@video) }
      format.json do
        payload = @stats.map { |s| video_stat_json(s) }
        render json: payload
      end
    end
  end

  def panes
    ids = params[:ids].to_s.split(/[\s,+]+/).reject(&:blank?)

    if ids.size <= 1
      if ids.first
        # Phase 20 — friendly URLs. Resolve the input (slug or integer
        # id) to the canonical record so the redirect target is the
        # slug URL, not whatever shape the caller passed in.
        record = begin
          Video.friendly.find(ids.first)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        redirect_to record ? video_path(record) : videos_path
      else
        redirect_to videos_path
      end
      return
    end

    @max_panes = max_panes
    @current_ids = ids.first(@max_panes)
    # Phase 20 — friendly URLs. Pane keys arrive as either integer ids
    # or slug strings (`youtube_video_id`). `friendly.find` resolves
    # both; missing keys collapse to nil for placeholder rendering.
    @panes = @current_ids.map do |key|
      Video.friendly.find(key)
    rescue ActiveRecord::RecordNotFound
      nil
    end
    @resolved_pane_ids = @panes.compact.map(&:id)
    @pane_title_length = pane_title_length
    @available_videos = Video.where.not(id: @resolved_pane_ids).order(created_at: :desc).limit(50) if @panes.compact.size < @max_panes
    @saved_view = SavedView.find_by(kind: :videos, url: CGI.unescape(request.fullpath))
  end

  # Phase 23 §23b — paginated index of every open VideoDiff (locked
  # Q3). One row per video with an unresolved diff; clicking the row
  # opens the per-video diff page. JSON branch returns the same shape
  # for the CLI lane.
  def diffs
    page = params[:page].to_i
    page = 1 if page < 1
    per_page = 50
    offset = (page - 1) * per_page

    base = VideoDiff.open.includes(video: :channel)
                    .order(detected_at: :desc)

    @total_count = base.count
    @page = page
    @per_page = per_page
    @total_pages = (@total_count.to_f / per_page).ceil
    @diffs = base.offset(offset).limit(per_page)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          page: @page,
          per_page: @per_page,
          total_count: @total_count,
          total_pages: @total_pages,
          diffs: @diffs.map { |d| diff_index_json(d) }
        }
      end
    end
  end

  # Phase 23 §23b — render the three-column reconciliation page when
  # an open `VideoDiff` exists. If none is open, redirect back to the
  # video show with a flash. The JSON branch returns a shape that
  # mirrors the `video_diff_show` MCP tool so the CLI lane and the
  # web lane share the same data contract.
  def diff
    return if redirect_to_canonical_slug!(@video) { |v| diff_video_path(v) }

    @diff = @video.open_diff

    respond_to do |format|
      format.html do
        if @diff.nil?
          redirect_to video_path(@video), notice: "no open diff for this video."
        end
      end
      format.json do
        if @diff
          render json: diff_detail_json(@video, @diff)
        else
          render json: { error: "no_open_diff" }, status: :not_found
        end
      end
    end
  end

  # Phase 23 §23c — consume the per-field decisions form and run the
  # apply orchestrator. The form sends one radio per row keyed
  # `decisions[<field>]` with value `"pito"` / `"youtube"`. JSON
  # parity: PATCH /videos/:slug/diff.json accepts the same shape
  # (`{ "decisions": { "<field>": "pito" | "youtube" } }`) and is
  # used by the CLI / MCP path. Boundary booleans serialize as
  # `"yes"` / `"no"` per the project-wide rule — none here, but the
  # decision values themselves are NOT yes/no (locked spec language).
  def apply_diff
    @diff = @video.open_diff

    if @diff.nil?
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: "no open diff to apply." }
        format.json { render json: { error: "no_open_diff" }, status: :not_found }
      end
      return
    end

    decisions = extract_decisions_param

    result = Channel::Youtube::VideoDiffApply.call(
      video_diff: @diff,
      decisions: decisions,
      user: Current.user
    )

    if result.success?
      message = build_apply_success_message(result)
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: message }
        format.json do
          render json: { ok: true, message: message,
                         pito_wins_fields: result.pito_wins_fields,
                         youtube_wins_fields: result.youtube_wins_fields }
        end
      end
    else
      respond_to do |format|
        format.html do
          flash.now[:alert] = result.error_message
          @apply_error_code = result.error_code
          render :diff, status: :unprocessable_content
        end
        format.json do
          render json: { ok: false, error: result.error_code,
                         message: result.error_message },
                 status: :unprocessable_content
        end
      end
    end
  end

  private

  # Phase 23 §23b — extract the decisions hash from form params,
  # normalizing into a plain Hash<String, String>. The JSON branch
  # may pass either a flat `decisions: {...}` or an outer wrapper
  # under the resource key; accept both.
  def extract_decisions_param
    raw = params[:decisions]
    raw ||= params.dig(:video_diff, :decisions)
    return {} if raw.blank?

    case raw
    when ActionController::Parameters
      raw.to_unsafe_h.transform_values(&:to_s)
    when Hash
      raw.transform_values(&:to_s)
    else
      {}
    end
  end

  def build_apply_success_message(result)
    pito_n    = Array(result.pito_wins_fields).size
    youtube_n = Array(result.youtube_wins_fields).size

    parts = []
    parts << "#{youtube_n} field#{'s' if youtube_n != 1} accepted from youtube" if youtube_n.positive?
    parts << "#{pito_n} field#{'s' if pito_n != 1} pushed to youtube"            if pito_n.positive?

    "diff resolved (#{parts.join(', ')})"
  end

  def diff_index_json(diff)
    video = diff.video
    {
      diff_id: diff.id,
      video_id: video.id,
      video_slug: video.to_param,
      youtube_video_id: video.youtube_video_id,
      title: video.title,
      channel_id: video.channel_id,
      channel_url: video.channel&.channel_url,
      detected_at: diff.detected_at&.iso8601,
      fields: diff.fields,
      diff_url: "/videos/#{video.to_param}/diff"
    }
  end

  def diff_detail_json(video, diff)
    {
      diff_id: diff.id,
      video_id: video.id,
      video_slug: video.to_param,
      youtube_video_id: video.youtube_video_id,
      title: video.title,
      detected_at: diff.detected_at&.iso8601,
      fields: diff.fields,
      payload: diff.payload,
      writable_fields: Channel::Youtube::DiffComputer::WRITABLE_FIELDS,
      display_only_fields: Channel::Youtube::DiffComputer::DISPLAY_ONLY_FIELDS
    }
  end


  def load_video
    @video = Video.friendly.find(params[:id])
  end

  # Phase 14 §3 — populate the edit-form view bag with the linked
  # games/bundles fieldset data. (D18 2026-05-21 — Project dropdown
  # dropped alongside Projects.)
  def load_edit_form_locals
    @video_links = @video.video_game_links.includes(:game, :bundle).order(:id)
    @link_pickable_games = Game.order(:title).limit(500)
    @link_pickable_bundles = Bundle.order(:name).limit(500)
  end

  # Phase 11 §01a — end-screen collapse on `kind: none`.
  #
  # When the user toggles `kind: none` on any submitted row, the
  # model invariant "no mixing none with other kinds" forbids the
  # other non-none rows from sticking around. The form cannot
  # destroy rows the user did not interact with, so the controller
  # collapses server-side:
  #   1. Drop / `_destroy` every submitted row that isn't the none
  #      row.
  #   2. Append `_destroy` rows for every persisted non-none end-
  #      screen that wasn't already in the submitted set.
  def collapse_end_screens_if_none!(raw_video_params)
    nested = raw_video_params[:video_end_screens_attributes]
    return if nested.blank?
    return unless nested.is_a?(Hash)

    rows = nested.to_h
    none_key = rows.find { |_, r| r.is_a?(Hash) && r[:kind].to_s == "none" }&.first
    return unless none_key

    submitted_ids = rows.values.filter_map { |r| r.is_a?(Hash) && r[:id].presence }
                                .map(&:to_i)

    rows.each do |key, row|
      next unless row.is_a?(Hash)
      next if key == none_key

      if row[:id].present?
        row[:_destroy] = "1"
      else
        rows.delete(key)
      end
    end

    next_index = rows.keys.map(&:to_i).max.to_i + 1
    @video.video_end_screens.where.not(kind: VideoEndScreen.kinds[:none]).each do |es|
      next if submitted_ids.include?(es.id)
      rows[next_index.to_s] = { "id" => es.id.to_s, "_destroy" => "1" }
      next_index += 1
    end

    raw_video_params[:video_end_screens_attributes] = rows
  end

  def max_panes
    # Phase 29 (settings refactor) — read from `config/pito.yml` via
    # `Rails.application.config.x.pito.max_panes`.
    Rails.application.config.x.pito.max_panes
  end

  def pane_title_length
    # Phase 29 (settings refactor) — see `max_panes` above.
    Rails.application.config.x.pito.pane_title_length
  end

  def sanitized_sort_key
    ALLOWED_SORTS.key?(params[:sort]) ? params[:sort] : DEFAULT_SORT
  end

  def sanitized_dir
    requested = params[:dir]&.downcase
    ALLOWED_DIRS.include?(requested) ? requested : DEFAULT_DIR
  end

  def sort_clause
    column = ALLOWED_SORTS[params[:sort]] || ALLOWED_SORTS[DEFAULT_SORT]
    direction = ALLOWED_DIRS.include?(params[:dir]&.downcase) ? params[:dir].downcase : DEFAULT_DIR
    Arel.sql("#{column} #{direction}")
  end

  def video_stat_json(stat)
    {
      date: stat.date.iso8601,
      views: stat.views.to_i,
      likes: stat.likes.to_i,
      comments: stat.comments.to_i,
      watch_time_minutes: stat.watch_time_minutes.to_f
    }
  end

  # The `update` action MUST NOT change privacy_status / publish_at.
  # Those are publish-flow / schedule-flow paths only. A submitted
  # value here means a malicious or buggy caller is attempting to
  # smuggle a publish-state transition past the checklist.
  def smuggled_publish_state?
    fields = params.fetch(:video, {})
    fields.key?(:privacy_status) || fields.key?("privacy_status") ||
      fields.key?(:publish_at) || fields.key?("publish_at")
  end

  def render_smuggle_error
    msg = "use [ publish ] or [ schedule ] to change privacy_status or publish_at."
    respond_to do |format|
      format.html do
        # Mirror `update`'s validation-error path — the edit template
        # renders the linked-games/bundles fieldset (Phase 14 §3) plus
        # the Phase 11 §01a chapters / end-screens nested editors,
        # which need the same view-bag the regular failure render
        # populates.
        load_edit_form_locals
        @video_chapters = @video.video_chapters.order(:start_seconds).to_a
        @video_end_screens = @video.video_end_screens.order(:position, :id).to_a
        @video.errors.add(:base, msg)
        render :edit, status: :unprocessable_content
      end
      format.json { render json: { errors: [ msg ] }, status: :unprocessable_content }
    end
  end

  def validate_publish(perms, video)
    %i[pre_publish_game_ok pre_publish_age_ok
       pre_publish_paid_promotion_ok pre_publish_end_screen_ok].each do |k|
      return "#{k} must be 'yes'" unless YesNo.from_yes_no(perms[k])
    end
    target = perms[:target_privacy_status].to_s
    return "target_privacy_status is required" if target.blank?
    unless PRIVACY_VALUES_FOR_PUBLISH.include?(target)
      return "target_privacy_status must be 'public' or 'unlisted'"
    end
    unless video.privacy_private?
      return "only private videos can be published"
    end
    nil
  end

  def validate_schedule(perms, video)
    %i[pre_publish_game_ok pre_publish_age_ok
       pre_publish_paid_promotion_ok pre_publish_end_screen_ok].each do |k|
      return "#{k} must be 'yes'" unless YesNo.from_yes_no(perms[k])
    end
    return "publish_at is required" if perms[:publish_at].blank?
    parsed, err = parsed_publish_at_with_error(perms[:publish_at])
    return err if err
    return "publish_at must be a valid ISO 8601 timestamp" if parsed.nil?
    return "publish_at must be in the future" if parsed <= Time.current
    unless video.privacy_private?
      return "only private videos can be scheduled"
    end
    nil
  end

  def render_publish_error(message, target_action: "publish")
    respond_to do |format|
      format.html do
        flash.now[:alert] = message
        @target_action = target_action
        render partial: "videos/pre_publish_modal",
               locals: { video: @video, target_action: target_action, error: message },
               status: :unprocessable_content
      end
      format.json do
        render json: { errors: [ message ] }, status: :unprocessable_content
      end
    end
  end

  # Form params arrive as either ActionController::Parameters strings or
  # raw values. Boundary discipline maps "yes" / "no" → boolean.
  def yes_no_attr(value)
    YesNo.from_yes_no(value)
  end

  # Phase 26 — 01h. The schedule form sends `publish_at` as a
  # `datetime-local` value (`"2026-06-01T09:00"`), interpreted as the
  # user's local clock. UTC ISO 8601 inputs (with a `Z` or explicit
  # offset suffix) keep the literal interpretation for JSON / MCP
  # callers; tz-less inputs route through `ScheduledPublishHelper` so
  # the user's stored `time_zone` is honored. DST spring-forward gaps
  # surface as a friendly error; DST fall-back resolves to the first
  # occurrence with a warning.
  #
  # Returns `[Time | nil, String | nil]`: the UTC instant + an
  # optional error message. The caller decides whether to surface the
  # error or proceed.
  def parsed_publish_at_with_error(value)
    return [ nil, nil ] if value.blank?

    str = value.to_s

    # An offset suffix or trailing `Z` means the caller specified the
    # absolute instant. Honor it as-is.
    if str.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/)
      begin
        return [ Time.iso8601(str), nil ]
      rescue ArgumentError
        begin
          return [ Time.zone.parse(str), nil ]
        rescue ArgumentError, TypeError
          return [ nil, "publish_at must be a valid ISO 8601 timestamp" ]
        end
      end
    end

    user_tz = Current.user&.time_zone.presence || "Etc/UTC"
    begin
      result = parse_user_local_to_utc(str, nil, user_tz)
      return [ nil, "publish_at must be a valid ISO 8601 timestamp" ] if result.nil?
      [ result.utc, nil ]
    rescue ScheduledPublishHelper::AmbiguousLocalTime => e
      [ nil, e.message ]
    end
  end

  # Back-compat wrapper used by `validate_schedule` and `schedule` —
  # callers that just want the parsed Time discard the error string.
  def parsed_publish_at(value)
    parsed_publish_at_with_error(value).first
  end
end
