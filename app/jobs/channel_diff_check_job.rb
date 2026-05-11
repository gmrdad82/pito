# Phase 7.5 — Step 11i (Daily Channel Diff-Check + Resolution).
#
# Sidekiq job with two invocation modes:
#
#   - **Cron mode** (`perform()` with no args): iterates every
#     `Channel.where.not(youtube_connection_id: nil)`. Per-channel
#     failures are isolated — a `TransientError` on one channel does
#     NOT abort the whole cron pass. `QuotaExhaustedError` aborts the
#     remaining iteration so Sidekiq doesn't burn retries on a known-
#     exhausted quota.
#   - **Single-channel mode** (`perform(channel_id)`): used by tests
#     and by the user-triggered `[sync]` button path. Errors propagate
#     to the caller / Sidekiq retry policy.
#
# Per-channel sequence:
#   1. Fetch authoritative state via `Youtube::Client#fetch_channel`.
#   2. Silently refresh statistics columns
#      (`subscriber_count`, `view_count`, `video_count`,
#      `hidden_subscriber_count`) — these are display-only and never
#      participate in the diff.
#   3. Compute the diff via `Channels::DiffComputer`.
#   4. Persist via `Channels::DiffPersister`. Empty diff → auto-close
#      any prior open row.
#   5. On a non-empty diff, fire a `channel_diff_detected`
#      notification IF the row is fresh OR the field set expanded
#      relative to its prior state (locked Q1 dedupe).
#   6. Broadcast a Turbo Stream replacing `#channel_diff_banner` on
#      the channel show page so the user sees the banner without
#      reloading.
class ChannelDiffCheckJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  # Statistics columns updated silently on every cron pass; never
  # surface in the diff.
  STATISTICS_FIELDS = %i[
    subscriber_count view_count video_count hidden_subscriber_count
  ].freeze

  def perform(channel_id = nil)
    if channel_id
      process_one(Channel.find_by(id: channel_id))
    else
      process_all
    end
  end

  private

  def process_all
    Channel.where.not(youtube_connection_id: nil).find_each do |channel|
      begin
        process_one(channel, single_channel_mode: false)
      rescue Youtube::QuotaExhaustedError => e
        Rails.logger.warn(
          "[ChannelDiffCheckJob] quota exhausted on channel=#{channel.id}; " \
          "aborting cron iteration: #{e.message}"
        )
        raise
      rescue Youtube::TransientError => e
        Rails.logger.warn(
          "[ChannelDiffCheckJob] transient error on channel=#{channel.id}; " \
          "skipping: #{e.class}: #{e.message}"
        )
        next
      end
    end
  end

  def process_one(channel, single_channel_mode: true)
    unless channel
      Rails.logger.warn("ChannelDiffCheckJob: channel not found; skipping")
      return nil
    end

    if channel.youtube_connection_id.nil?
      Rails.logger.warn(
        "ChannelDiffCheckJob: channel##{channel.id} has no youtube_connection; skipping"
      )
      return nil
    end

    connection = channel.youtube_connection
    if connection.needs_reauth?
      Rails.logger.warn(
        "ChannelDiffCheckJob: channel##{channel.id} connection needs re-auth; skipping"
      )
      return nil
    end

    payload = begin
      Youtube::Client.new(connection).fetch_channel(channel)
    rescue Youtube::NeedsReauthError, Youtube::AuthRevokedError => e
      Rails.logger.warn(
        "[ChannelDiffCheckJob] channel##{channel.id} auth revoked; flipping " \
        "connection.needs_reauth=true. #{e.class}: #{e.message}"
      )
      connection.update_columns(needs_reauth: true)
      return nil
    end

    refresh_statistics!(channel, payload)

    prior_fields = channel.channel_diffs.unresolved.first&.field_diffs&.keys || []

    field_diffs = Channels::DiffComputer.call(channel, payload)
    diff = Channels::DiffPersister.call(
      channel: channel,
      field_diffs: field_diffs
    )

    if diff
      emit_diff_notification(channel, diff, prior_fields: prior_fields)
    end

    broadcast_banner(channel, diff, single_channel_mode: single_channel_mode)

    diff
  end

  # Refresh the four display-only statistics columns. Use
  # `update_columns` so callbacks (notifications, calendar derivation,
  # etc.) don't fire on a silent stats refresh. Per Channel validators
  # the columns are nullable / numeric with a non-negative gate; the
  # YouTube response is already coerced by `normalize_channel_item`.
  def refresh_statistics!(channel, payload)
    return unless payload.is_a?(Hash)

    payload = payload.symbolize_keys if payload.respond_to?(:symbolize_keys)
    attrs = STATISTICS_FIELDS.each_with_object({}) do |field, h|
      h[field] = payload[field] if payload.key?(field)
    end
    return if attrs.empty?

    channel.update_columns(attrs)
  end

  # Phase 16 §1 — Notification row. Dedup posture (locked Q1): emit
  # only when the row is FRESH (created in this pass; no prior open
  # row) OR when the new diffing field set is a strict expansion of
  # the prior set. Same-set / contracted set → no new notification.
  def emit_diff_notification(channel, diff, prior_fields:)
    new_fields = Array(diff.field_diffs.keys)
    return if dedupe_notification?(prior_fields, new_fields)

    Notification.create!(
      kind: :channel_diff_detected,
      event_type: "channel_diff_detected",
      severity: :info,
      title: "youtube diverged on #{new_fields.size} field#{'s' if new_fields.size != 1}",
      body: "channel '#{channel_label(channel)}' has #{new_fields.size} " \
            "pending diff field#{'s' if new_fields.size != 1}.",
      url: "/channels/#{channel.to_param}/diff",
      fires_at: Time.current,
      dedup_key: "channel_diff:#{channel.id}:#{diff.id}:#{new_fields.sort.join(',')}",
      event_payload: {
        channel_id: channel.id,
        channel_slug: channel.to_param,
        channel_title: channel.title,
        channel_url: channel.channel_url,
        diff_id: diff.id,
        fields: new_fields
      }
    )
  rescue ActiveRecord::RecordNotUnique
    # `dedup_key` unique partial index lost the race. Idempotency net.
    nil
  end

  def dedupe_notification?(prior_fields, new_fields)
    prior = prior_fields.to_set
    fresh = new_fields.to_set
    return false if prior.empty?           # fresh row — always notify
    return true  if fresh.subset?(prior)   # same or contracted — skip
    false                                  # expansion — notify
  end

  def channel_label(channel)
    channel.title.presence || channel.handle.presence || channel.channel_url
  end

  # Broadcast a Turbo Stream replace into the `channel_diff_banner`
  # frame on the channel show page. Targets the per-channel stream
  # name `"channel_#{channel.id}_diff_banner"` which the show page
  # subscribes to via `turbo_stream_from`. The view layer (11b) ships
  # the empty frame; 11i owns the broadcast contract.
  def broadcast_banner(channel, diff, single_channel_mode:)
    return unless single_channel_mode

    if diff
      Turbo::StreamsChannel.broadcast_replace_to(
        channel_diff_stream_name(channel),
        target: "channel_diff_banner",
        partial: "channels/open_diff_banner",
        locals: { channel: channel, diff: diff }
      )
    else
      Turbo::StreamsChannel.broadcast_replace_to(
        channel_diff_stream_name(channel),
        target: "channel_diff_banner",
        partial: "channels/in_sync_banner",
        locals: { channel: channel }
      )
    end
  rescue StandardError => e
    Rails.logger.warn(
      "[ChannelDiffCheckJob] turbo broadcast failed for channel=#{channel.id}: " \
      "#{e.class}: #{e.message}"
    )
  end

  def channel_diff_stream_name(channel)
    "channel_#{channel.id}_diff_banner"
  end
end
