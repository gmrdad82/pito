# Phase 12 — single source of truth for the writable-field set on
# Video. VideosController references this so the metadata-edit
# permitted attributes stay in sync across the web surface (locked
# decision #2).
#
# This is NOT Pundit. It is a small, self-contained module that
# exposes:
#
#   - VideoPolicy::EDITABLE_ATTRS — the array of attribute names a
#     metadata edit may set.
#   - VideoPolicy::SMUGGLE_GUARDED_ATTRS — attributes the controller
#     must explicitly reject (privacy_status, publish_at) because
#     they belong to the publish / schedule flow.
#   - VideoPolicy::SYSTEM_MANAGED_ATTRS — attributes the user can
#     never set; the strong-params filter silently drops them.
#   - VideoPolicy::PUBLISH_ATTRS / SCHEDULE_ATTRS — attributes that
#     fly through the publish / schedule actions specifically.
#   - .permit(params) — Action Controller-friendly helper.
module VideoPolicy
  EDITABLE_ATTRS = %i[
    title description category_id project_id
    self_declared_made_for_kids contains_synthetic_media
    thumbnail
  ].freeze

  # Phase 11 §01a — nested attributes for chapters + end-screens.
  # Keys mirror the model's `accepts_nested_attributes_for` config.
  EDITABLE_ARRAY_ATTRS = {
    tags: [],
    video_chapters_attributes: %i[id start_seconds label position _destroy],
    video_end_screens_attributes: %i[id kind target_id target_label position _destroy]
  }.freeze

  SMUGGLE_GUARDED_ATTRS = %i[privacy_status publish_at].freeze

  SYSTEM_MANAGED_ATTRS = %i[
    youtube_video_id channel_id youtube_connection_id
    etag last_synced_at made_for_kids_effective last_sync_error
    pre_publish_checked_at
    pre_publish_game_ok pre_publish_age_ok
    pre_publish_paid_promotion_ok pre_publish_end_screen_ok
  ].freeze

  PUBLISH_ATTRS = %i[
    pre_publish_game_ok pre_publish_age_ok
    pre_publish_paid_promotion_ok pre_publish_end_screen_ok
    target_privacy_status
  ].freeze

  SCHEDULE_ATTRS = %i[
    pre_publish_game_ok pre_publish_age_ok
    pre_publish_paid_promotion_ok pre_publish_end_screen_ok
    publish_at
  ].freeze

  module_function

  def permit(params)
    attrs = params.permit(*EDITABLE_ATTRS, **EDITABLE_ARRAY_ATTRS)
    SYSTEM_MANAGED_ATTRS.each { |k| attrs.delete(k) }
    SMUGGLE_GUARDED_ATTRS.each { |k| attrs.delete(k) }
    attrs
  end

  def permit_publish(params)
    params.permit(*PUBLISH_ATTRS)
  end

  def permit_schedule(params)
    params.permit(*SCHEDULE_ATTRS)
  end

  # MCP-side filter — operates on a plain Hash (whatever the tool
  # received as kwargs). Returns the writable-field subset only;
  # rejected keys are silently dropped (system-managed) or rejected
  # explicitly (publish_at / privacy_status — caller checks).
  def filter_mcp_input(input)
    out = {}
    input.each do |key, value|
      key_sym = key.to_sym
      next unless EDITABLE_ATTRS.include?(key_sym) || key_sym == :tags
      out[key_sym] = value
    end
    out
  end
end
