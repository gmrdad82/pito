class ChannelsController < ApplicationController
  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON requests so the HTML form path keeps
  # its authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  ALLOWED_SORTS = {
    "created_at" => "channels.created_at",
    "updated_at" => "channels.updated_at",
    "last_synced_at" => "channels.last_synced_at",
    "channel_url" => "channels.channel_url"
  }.freeze
  ALLOWED_DIRS = %w[asc desc].freeze

  def index
    @max_panes = max_panes
    @saved_views = SavedView.channels.ordered

    scope = Channel.all
    scope = scope.where(star: true)      if filter_on?(:star)
    scope = scope.where(connected: true) if filter_on?(:connected)
    scope = scope.where(syncing: true)   if filter_on?(:syncing)

    @channels = scope.order(sort_clause)
    @filters = active_filters

    respond_to do |format|
      format.html
      format.json { render json: @channels.map { |c| ChannelDecorator.new(c).as_summary_json } }
    end
  end

  def show
    @channel = Channel.find(params[:id])
    @max_panes = max_panes
    @available_channels = Channel.where.not(id: @channel.id).order(:channel_url)

    respond_to do |format|
      format.html
      format.json { render json: ChannelDecorator.new(@channel).as_detail_json }
    end
  end

  def new
    @channel = Channel.new
  end

  def create
    bool_attrs, error = coerce_yes_no_attrs(%i[star connected])
    if error
      respond_to do |format|
        format.html { redirect_to channels_path, alert: error }
        format.json { render json: { errors: [ error ] }, status: :unprocessable_entity }
      end
      return
    end

    @channel = Channel.new(create_params.merge(bool_attrs))
    @channel.tenant ||= default_tenant
    if @channel.save
      respond_to do |format|
        format.html { redirect_to channel_path(@channel), notice: "channel created." }
        format.json { render json: ChannelDecorator.new(@channel).as_detail_json, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @channel.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @channel = Channel.find(params[:id])
  end

  def update
    @channel = Channel.find(params[:id])

    attrs, error = coerce_update_attrs
    if error
      respond_to do |format|
        format.html { redirect_to channel_path(@channel), alert: error }
        format.json { render json: { errors: [ error ] }, status: :unprocessable_entity }
      end
      return
    end

    if @channel.update(attrs)
      respond_to do |format|
        format.html { redirect_to channel_path(@channel), notice: "channel updated." }
        format.json { render json: ChannelDecorator.new(@channel).as_detail_json }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @channel.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @channel = Channel.find(params[:id])
    @channel.destroy
    respond_to do |format|
      format.html { redirect_to channels_path, notice: "channel deleted." }
      format.json { head :no_content }
    end
  end

  # GET /channels/:id/videos(.json)
  #
  # Returns the videos belonging to the given channel. Used by pito-sh to
  # populate per-channel video lists. JSON shape mirrors VideosController#index
  # so the same Rust `Video` struct decodes either response.
  def videos
    @channel = Channel.find(params[:id])
    @videos = @channel.videos
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
      )
      .group("videos.id")
      .order(published_at: :desc)

    respond_to do |format|
      format.html { redirect_to channel_path(@channel) }
      format.json { render json: @videos.map { |v| VideoDecorator.new(v).as_summary_json } }
    end
  end

  def panes
    ids = params[:ids].to_s.split(/[\s,+]+/).reject(&:blank?)

    if ids.size <= 1
      redirect_to ids.first ? channel_path(ids.first) : channels_path
      return
    end

    @max_panes = max_panes
    @current_ids = ids.first(@max_panes)
    @panes = @current_ids.map { |id| Channel.find_by(id: id) }
    @pane_title_length = pane_title_length
    @available_channels = Channel.where.not(id: @current_ids).order(:channel_url) if @panes.compact.size < @max_panes
    @saved_view = SavedView.find_by(kind: :channels, url: CGI.unescape(request.fullpath))
  end

  private

  def max_panes
    (AppSetting.get("max_panes") || ENV.fetch("MAX_PANES", 3)).to_i
  end

  def pane_title_length
    (AppSetting.get("pane_title_length") || ENV.fetch("PANE_TITLE_LENGTH", 14)).to_i
  end

  def create_params
    params.require(:channel).permit(:channel_url)
  end

  # External JSON / form bodies must communicate booleans as the strings
  # "yes"/"no" (see app/lib/yes_no.rb). Returns [attrs, error].
  # `error` is non-nil when an invalid value was supplied.
  def coerce_update_attrs
    coerce_yes_no_attrs(%i[star connected])
  end

  # Generic yes/no coercion for the `:channel` params block. Reads only the
  # listed keys, rejects any non-"yes"/"no" value, and returns coerced
  # booleans suitable for ActiveRecord assignment. Returns [attrs, error].
  def coerce_yes_no_attrs(keys)
    raw = params[:channel]
    return [ {}, nil ] unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

    attrs = {}
    keys.each do |key|
      next unless raw.key?(key)
      value = raw[key]
      unless YesNo.yes_no?(value)
        return [ nil, "#{key} must be 'yes' or 'no' (got #{value.inspect})" ]
      end
      attrs[key] = YesNo.from_yes_no(value)
    end
    [ attrs, nil ]
  end

  # URL filter params use the "yes"/"no" convention strictly. Only the
  # literal string "yes" enables a filter; anything else (including "1",
  # "true", "on") is treated as no filter.
  def filter_on?(key)
    YesNo.from_yes_no(params[key])
  end

  def active_filters
    %i[star connected syncing].select { |k| filter_on?(k) }
  end

  def default_tenant
    # Single-tenant for now (see CLAUDE.md). The first tenant is the workspace
    # owner; future multi-tenancy will replace this with a request-scoped lookup.
    Tenant.order(:id).first || Tenant.create!(name: "Primary")
  end

  def sort_clause
    column = ALLOWED_SORTS[params[:sort]] || ALLOWED_SORTS["created_at"]
    direction = ALLOWED_DIRS.include?(params[:dir]&.downcase) ? params[:dir].downcase : "desc"
    Arel.sql("#{column} #{direction}")
  end
end
