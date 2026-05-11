class ChannelsController < ApplicationController
  include FriendlyRedirect

  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON requests so the HTML form path keeps
  # its authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  ALLOWED_SORTS = {
    "id" => "channels.id",
    "created_at" => "channels.created_at",
    "updated_at" => "channels.updated_at",
    "last_synced_at" => "channels.last_synced_at",
    "channel_url" => "channels.channel_url",
    "starred" => "channels.star"
  }.freeze
  ALLOWED_DIRS = %w[asc desc].freeze
  DEFAULT_SORT = "created_at"
  DEFAULT_DIR = "desc"

  def index
    @max_panes = max_panes
    @saved_views = SavedView.channels.ordered

    scope = Channel.all
    scope = scope.where(star: true) if filter_on?(:star)

    @channels = scope.order(sort_clause)
    @filters = active_filters
    @sort = sanitized_sort_key
    @dir = sanitized_dir

    respond_to do |format|
      format.html
      format.json { render json: @channels.map { |c| ChannelDecorator.new(c).as_summary_json } }
    end
  end

  def show
    @channel = Channel.friendly.find(params[:id])
    return if redirect_to_canonical_slug!(@channel) { |c| channel_path(c) }

    @max_panes = max_panes
    @available_channels = Channel.where.not(id: @channel.id).order(:channel_url)

    respond_to do |format|
      format.html
      format.json { render json: ChannelDecorator.new(@channel).as_detail_json }
    end
  end

  def edit
    @channel = Channel.friendly.find(params[:id])
  end

  def update
    @channel = Channel.friendly.find(params[:id])

    # JSON callers (CLI / MCP) keep the original `star`-toggle path
    # with strict yes/no boundary semantics.
    if request.format.json?
      return update_via_json
    end

    # Legacy HTML `star`-toggle surface — the show page renders an
    # inline `[star]` / `[unstar]` form that submits `channel[star]`.
    # That flow never overlaps the 11c edit-form fields, so we
    # detect star-only submissions and route them through the
    # original yes/no boundary path.
    if star_only_html_request?
      return perform_star_toggle_html
    end

    if params[:channel].blank? || channel_form_fields_blank?
      redirect_to channel_path(@channel), notice: "no changes to save."
      return
    end

    if @channel.youtube_connection_id.nil?
      perform_local_only_update
    else
      perform_youtube_update
    end
  end

  def destroy
    @channel = Channel.friendly.find(params[:id])
    @channel.destroy
    respond_to do |format|
      format.html { redirect_to channels_path, notice: "channel deleted." }
      format.json { head :no_content }
    end
  end

  # Phase 7.5 §11i — render the three-column diff resolution page
  # when an open `ChannelDiff` exists for the channel. If none is
  # open, redirect back to the channel show with a flash notice. JSON
  # branch returns the same shape as the `channel_diff_show` MCP
  # tool so the CLI / Claude lanes share the contract.
  def diff
    @channel = Channel.friendly.find(params[:id])
    return if redirect_to_canonical_slug!(@channel) { |c| diff_channel_path(c) }

    @diff = @channel.open_channel_diff

    respond_to do |format|
      format.html do
        if @diff.nil?
          redirect_to channel_path(@channel), notice: "no open diff for this channel."
        end
      end
      format.json do
        if @diff
          render json: diff_detail_json(@channel, @diff)
        else
          render json: { error: "no_open_diff" }, status: :not_found
        end
      end
    end
  end

  # Phase 7.5 §11i — apply the per-field decisions form. The form
  # sends one radio per row keyed `decisions[<field>]` with value
  # `"pito"` / `"youtube"`. JSON parity: PATCH
  # /channels/:slug/apply_diff.json accepts the same shape and is
  # used by the MCP tool path. Per locked Q3, the apply is atomic —
  # the whole transaction rolls back on the first push failure.
  def apply_diff
    @channel = Channel.friendly.find(params[:id])
    @diff = @channel.open_channel_diff

    if @diff.nil?
      respond_to do |format|
        format.html { redirect_to channel_path(@channel), notice: "this diff was already resolved." }
        format.json { render json: { error: "no_open_diff" }, status: :not_found }
      end
      return
    end

    decisions = extract_diff_decisions_param

    result = Channels::DiffApply.call(
      channel_diff: @diff,
      decisions: decisions,
      user: Current.user
    )

    if result.success?
      message = build_diff_apply_success_message(result)
      respond_to do |format|
        format.html { redirect_to channel_path(@channel), notice: message }
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
          @apply_failing_field = result.failing_field
          render :diff, status: :unprocessable_content
        end
        format.json do
          render json: { ok: false, error: result.error_code,
                         message: result.error_message,
                         failing_field: result.failing_field },
                 status: :unprocessable_content
        end
      end
    end
  end

  # GET /channels/:id/videos(.json)
  #
  # Returns the videos belonging to the given channel. Used by the pito CLI
  # to populate per-channel video lists. JSON shape mirrors
  # VideosController#index so the same Rust `Video` struct decodes either
  # response.
  def videos
    @channel = Channel.friendly.find(params[:id])
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
      .order(created_at: :desc)

    respond_to do |format|
      format.html { redirect_to channel_path(@channel) }
      format.json { render json: @videos.map { |v| VideoDecorator.new(v).as_summary_json } }
    end
  end

  def panes
    ids = params[:ids].to_s.split(/[\s,+]+/).reject(&:blank?)

    if ids.size <= 1
      if ids.first
        # Phase 20 — friendly URLs. Resolve the input (slug or integer
        # id) to the canonical record so the redirect target is the
        # slug URL.
        record = begin
          Channel.friendly.find(ids.first)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        redirect_to record ? channel_path(record) : channels_path
      else
        redirect_to channels_path
      end
      return
    end

    @max_panes = max_panes
    @current_ids = ids.first(@max_panes)
    # Phase 20 — friendly URLs. Pane keys arrive as either integer ids
    # (legacy bookmarks) or UC-id slugs. `friendly.find` resolves both;
    # we swallow `RecordNotFound` so a missing pane shows up as nil and
    # the view renders a placeholder instead of 500ing the row.
    @panes = @current_ids.map do |key|
      Channel.friendly.find(key)
    rescue ActiveRecord::RecordNotFound
      nil
    end
    @resolved_pane_ids = @panes.compact.map(&:id)
    @pane_title_length = pane_title_length
    @available_channels = Channel.where.not(id: @resolved_pane_ids).order(:channel_url) if @panes.compact.size < @max_panes
    @saved_view = SavedView.find_by(kind: :channels, url: CGI.unescape(request.fullpath))
  end

  private

  # True when params[:channel] carries only the legacy `star` flag
  # (plus channel_url, which the boundary coercion silently drops).
  # The 11c edit-form fields never include `star`, so detecting this
  # shape lets us route the show-page star toggle through the
  # original yes/no boundary path without touching the new flow.
  def star_only_html_request?
    raw = params[:channel]
    return false unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)
    return false unless raw.key?(:star) || raw.key?("star")
    edit_form_keys = PERMITTED_EDIT_KEYS + %i[
      watermark watermark_remove links_attributes banner banner_image
    ]
    raw_keys = raw.to_unsafe_h.keys.map(&:to_sym) - [ :channel_url, :star ]
    (raw_keys & edit_form_keys).empty?
  end

  # Legacy HTML `star`-toggle path — mirrors the pre-11c
  # `@channel.update(attrs)` flow. Re-uses `coerce_update_attrs` so
  # the historical yes/no boundary tests stay green.
  def perform_star_toggle_html
    attrs, error = coerce_update_attrs
    if error
      redirect_to channel_path(@channel), alert: error
      return
    end

    if @channel.update(attrs)
      redirect_to channel_path(@channel), notice: "channel updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # JSON path — preserves the pre-11c yes/no boundary contract. The
  # JSON callers (CLI / MCP) only ever toggle `star`; anything else in
  # the body is silently ignored. The dispatcher mirrors the original
  # `coerce_update_attrs` + `@channel.update(attrs)` flow so the
  # historical request specs keep their semantics.
  def update_via_json
    attrs, error = coerce_update_attrs
    if error
      render json: { errors: [ error ] }, status: :unprocessable_content
      return
    end

    if @channel.update(attrs)
      render json: ChannelDecorator.new(@channel).as_detail_json
    else
      render json: { errors: @channel.errors.full_messages }, status: :unprocessable_content
    end
  end

  # HTML path, local-only branch — the channel has no Google identity
  # linked, so the dirty subset writes straight into the cache columns
  # with no YouTube push. The user lands back on the show page with a
  # flash explaining the channel is unlinked.
  def perform_local_only_update
    attrs = channel_edit_attrs
    if @channel.update(attrs)
      redirect_to channel_path(@channel),
                  notice: "channel updated locally — connect a google identity to push changes to youtube."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # HTML path, YouTube-linked branch — dispatches through
  # `Youtube::Client` and caches the response into the channel's local
  # columns. Order matters:
  #
  #   1. Watermark-remove (channel[watermark_remove] = "yes")
  #   2. Watermark-set (channel[watermark] file uploaded)
  #   3. Branding update (title / description / country / language /
  #      keywords — the dirty subset only)
  #   4. Local cache write (canonical values from YouTube's response)
  #
  # Defense-in-depth: when the 14-day gate is open on title or handle,
  # those fields are stripped from the dirty subset before dispatch
  # even if a bypass put them in the params. The view's gate hides the
  # inputs, but a malicious client could POST them anyway.
  def perform_youtube_update
    client = Youtube::Client.new(@channel.youtube_connection)
    raw_attrs = channel_edit_attrs

    gate_warnings = strip_gated_fields!(raw_attrs)

    new_banner_url = nil

    ::Channel.transaction do
      handle_watermark_unset!(client) if YesNo.from_yes_no(params.dig(:channel, :watermark_remove))
      handle_watermark_set!(client, raw_attrs) if watermark_upload_present?
      new_banner_url = handle_banner_upload!(client) if banner_upload_present?

      field_set = raw_attrs.slice(
        :title, :description, :country, :default_language, :keywords, :links
      ).compact.reject { |_, v| v == "" }

      if field_set.except(:links).any?
        # `links` is locally-validated jsonb — it does not flow through
        # `update_channel` (YouTube's API does not expose a stable
        # write path for the links array post-2024 redesign per the
        # parent spec's D13 verification note). The branding-keyed
        # subset is what goes over the wire.
        branding_keys = field_set.slice(:title, :description, :country, :default_language, :keywords)
        client.update_channel(@channel, branding_keys) if branding_keys.any?
      end

      cache_attrs = raw_attrs.dup
      cache_attrs[:banner_url] = new_banner_url if new_banner_url
      cache_attrs[:title_changed_at] = Time.current if raw_attrs.key?(:title) && raw_attrs[:title].present? && raw_attrs[:title] != @channel.title
      cache_attrs[:handle_changed_at] = Time.current if raw_attrs.key?(:handle) && raw_attrs[:handle].present? && raw_attrs[:handle] != @channel.handle

      unless @channel.update(cache_attrs)
        # Validation failure on the cache write — roll back the
        # YouTube push by raising. This is the rare "we pushed
        # successfully but local validation tripped" branch; in
        # practice the same validations run client-side and on the
        # destructive PUT, so this guards against a column drift.
        raise ActiveRecord::Rollback
      end
    end

    if @channel.errors.any?
      render :edit, status: :unprocessable_content
      return
    end

    notice = gate_warnings.any? ? gate_warnings.join(" ") : "channel updated."

    # Phase 7.5 §11f — when the only change was a banner upload, the
    # banner section swaps in-place via Turbo Stream instead of doing
    # a full-page reload. Falls back to the redirect-to-show flow for
    # every other shape.
    if new_banner_url && banner_upload_only?
      respond_to do |format|
        format.turbo_stream { render :banner_updated, locals: { channel: @channel } }
        format.html { redirect_to channel_path(@channel), notice: notice }
      end
      return
    end

    redirect_to channel_path(@channel), notice: notice
  rescue Youtube::NeedsReauthError
    @channel.youtube_connection.update_columns(needs_reauth: true)
    redirect_to settings_youtube_path,
                alert: "google connection needs re-authorization."
  rescue Youtube::QuotaExhaustedError
    flash.now[:alert] = "youtube api quota exhausted; try again later."
    render :edit, status: :unprocessable_content
  rescue Youtube::TransientError
    flash.now[:alert] = "youtube is having trouble right now; please try again in a few minutes."
    render :edit, status: :unprocessable_content
  rescue Youtube::PermanentError => e
    flash.now[:alert] = "youtube refused the update: #{e.message}"
    render :edit, status: :unprocessable_content
  rescue ArgumentError => e
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_content
  end

  def handle_watermark_unset!(client)
    client.unset_watermark(@channel)
    @channel.update_columns(
      watermark_url: nil,
      watermark_timing: nil,
      watermark_offset_ms: nil
    )
  end

  def handle_watermark_set!(client, raw_attrs)
    io = params[:channel][:watermark]
    timing = raw_attrs[:watermark_timing].presence || @channel.watermark_timing
    offset_ms = raw_attrs[:watermark_offset_ms]
    client.set_watermark(@channel, io, timing, offset_ms)
    raw_attrs.delete(:watermark) # never assign the IO to the AR model
  end

  def watermark_upload_present?
    file = params.dig(:channel, :watermark)
    file.respond_to?(:read) && file.respond_to?(:original_filename)
  end

  # Phase 7.5 §11f — true when the user picked a banner image and
  # POSTed it under `channel[banner_image]`. The Stimulus controller
  # only stages the file once client-side validation passes, so a
  # POST with `banner_image` present means the client checks already
  # cleared. Server-side validation still acts as the authoritative
  # gate per D14 — Youtube::Client raises a Permanent / Transient /
  # Auth error if YouTube rejects the bytes (e.g.
  # `imageDimensionsInvalid`).
  def banner_upload_present?
    file = params.dig(:channel, :banner_image)
    file.respond_to?(:read) && file.respond_to?(:original_filename)
  end

  def handle_banner_upload!(client)
    io = params[:channel][:banner_image]
    client.upload_banner(@channel, io)
  end

  # True iff the only meaningful field on this submission was the
  # banner image. Used to decide between the Turbo Stream banner-
  # section swap and the full redirect.
  def banner_upload_only?
    raw = params[:channel]
    return false unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)
    return false unless banner_upload_present?

    other_edit_keys = (PERMITTED_EDIT_KEYS + %i[watermark watermark_remove links_attributes]) - [ :banner_image ]
    raw_keys = raw.to_unsafe_h.keys.map(&:to_sym) - %i[channel_url banner_image]

    # `links_attributes` may be present as an empty trailing-row
    # array even when the user did not touch the links section;
    # filter those out so the banner-only path stays detectable.
    if raw_keys.include?(:links_attributes)
      normalized = normalize_links_attributes(raw[:links_attributes])
      raw_keys.delete(:links_attributes) if normalized.empty?
    end

    (raw_keys & other_edit_keys).empty?
  end

  def strip_gated_fields!(attrs)
    warnings = []
    if attrs.key?(:title) && helpers.title_gate_open?(@channel)
      attrs.delete(:title)
      unlock = helpers.title_unlock_date(@channel)
      warnings << "title is locked until #{unlock}; the other fields were saved."
    end
    if attrs.key?(:handle) && helpers.handle_gate_open?(@channel)
      attrs.delete(:handle)
      unlock = helpers.handle_unlock_date(@channel)
      warnings << "handle is locked until #{unlock}; the other fields were saved."
    end
    warnings
  end

  def channel_form_fields_blank?
    raw = params[:channel]
    return true unless raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)

    permitted = channel_edit_attrs
    permitted.compact.values.all? { |v| v.respond_to?(:empty?) ? v.empty? : v.nil? } &&
      !watermark_upload_present? &&
      !banner_upload_present? &&
      !YesNo.from_yes_no(params.dig(:channel, :watermark_remove))
  end

  # Strong params for the HTML edit form. Returns a plain Hash
  # (`to_h`) of permitted keys with `links` normalized into the jsonb
  # array shape that `Channel#links` validates against. The
  # `links_attributes` shape is the Rails-standard
  # `accepts_nested_attributes_for`-ish wire format with a `_destroy`
  # yes/no flag; the server filters destroyed rows before persisting.
  PERMITTED_EDIT_KEYS = %i[
    title handle description country default_language keywords
    watermark_timing watermark_offset_ms
  ].freeze

  def channel_edit_attrs
    return {} unless params[:channel].is_a?(ActionController::Parameters) || params[:channel].is_a?(Hash)

    raw = params.require(:channel).permit(
      *PERMITTED_EDIT_KEYS,
      links_attributes: %i[title url _destroy]
    )
    attrs = raw.to_h.symbolize_keys

    if attrs.key?(:links_attributes)
      attrs[:links] = normalize_links_attributes(attrs.delete(:links_attributes))
    end

    if attrs.key?(:watermark_offset_ms)
      attrs[:watermark_offset_ms] = attrs[:watermark_offset_ms].to_s.empty? ? nil : attrs[:watermark_offset_ms].to_i
    end

    attrs
  end

  # Convert the form's `links_attributes` hash (string-keyed by row
  # index, e.g. `"0" => { title:, url:, _destroy: }`) into the jsonb
  # array shape `Channel#links` validates. Rows flagged `_destroy: yes`
  # drop out; rows with both title and url blank also drop out
  # (treating the empty trailing-row case as a no-op rather than a
  # validation failure).
  def normalize_links_attributes(links_attributes)
    return [] if links_attributes.blank?

    rows = links_attributes.is_a?(Hash) ? links_attributes.values : Array(links_attributes)
    rows.reject do |row|
      destroy_flag = row["_destroy"] || row[:_destroy]
      destroy_flag && YesNo.from_yes_no(destroy_flag)
    end.reject do |row|
      (row["title"] || row[:title]).to_s.strip.empty? && (row["url"] || row[:url]).to_s.strip.empty?
    end.map do |row|
      {
        "title" => (row["title"] || row[:title]).to_s,
        "url"   => (row["url"]   || row[:url]).to_s
      }
    end
  end

  def max_panes
    (AppSetting.get("max_panes") || ENV.fetch("MAX_PANES", 3)).to_i
  end

  def pane_title_length
    (AppSetting.get("pane_title_length") || ENV.fetch("PANE_TITLE_LENGTH", 14)).to_i
  end

  # External JSON / form bodies must communicate booleans as the strings
  # "yes"/"no" (see app/lib/yes_no.rb). Returns [attrs, error].
  # `error` is non-nil when an invalid value was supplied.
  def coerce_update_attrs
    coerce_yes_no_attrs(%i[star])
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
    %i[star].select { |k| filter_on?(k) }
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

  # Phase 7.5 §11i — extract the decisions hash from form params,
  # normalizing into a plain Hash<String, String>. The JSON branch
  # may pass either a flat `decisions: {...}` or an outer wrapper
  # under the resource key; accept both.
  def extract_diff_decisions_param
    raw = params[:decisions]
    raw ||= params.dig(:channel_diff, :decisions)
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

  def build_diff_apply_success_message(result)
    pito_n    = Array(result.pito_wins_fields).size
    youtube_n = Array(result.youtube_wins_fields).size

    parts = []
    parts << "#{pito_n} field#{'s' if pito_n != 1} pushed to youtube"        if pito_n.positive?
    parts << "#{youtube_n} field#{'s' if youtube_n != 1} updated locally"   if youtube_n.positive?
    parts << "no changes" if parts.empty?

    "changes applied. #{parts.join(', ')}."
  end

  def diff_detail_json(channel, diff)
    {
      diff_id: diff.id,
      channel_id: channel.id,
      channel_slug: channel.to_param,
      channel_url: channel.channel_url,
      title: channel.title,
      detected_at: diff.detected_at&.iso8601,
      fields: diff.fields,
      field_diffs: diff.field_diffs,
      writable_fields: Channels::DiffApply::BRANDING_PUSH_FIELDS +
                       [ Channels::DiffApply::HANDLE_FIELD ],
      unsupported_pito_fields: Channels::DiffApply::UNSUPPORTED_PITO_FIELDS
    }
  end
end
