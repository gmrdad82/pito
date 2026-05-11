# Phase 24 — bulk `[revoke N]` flow on `/channels`.
#
# Mirrors `ChannelRevokesController` but accepts a comma-separated
# `:ids` list per `CLAUDE.md` bulk-as-foundation. Single-element bulk
# (one id) renders the same modal in single-channel mode; N-element
# bulk renders an aggregated count block + a list of channels capped
# at the first 10 with an `…and M more` tail. Confirming enqueues one
# `DeleteChannelDataJob` per channel; the job's idempotency +
# connection orphan-check handle interleaving when channels share a
# connection.
class Channels::BulkRevokesController < ApplicationController
  # Display cap for the channel list in the bulk modal. Beyond this
  # threshold the modal renders `…and M more`. Architect locked 10
  # in the umbrella spec (5 was the Settings Google card cap; bulk
  # revoke benefits from a higher cap because users are reading
  # consequences, not summaries).
  PREVIEW_CAP = 10

  # GET /channels/revokes/:ids
  def show
    ids = parse_ids
    @channels = Channel.where(id: ids).order(channel_url: :asc).to_a

    if @channels.empty?
      redirect_to channels_path, alert: "nothing to revoke."
      return
    end

    @counts = ChannelRevokeCounts.for_many(@channels)
    @preview_channels = @channels.first(PREVIEW_CAP)
    @overflow_count = [ @channels.length - PREVIEW_CAP, 0 ].max
    @orphan_connections = compute_orphan_connections(@channels)

    render :show
  end

  # POST /channels/revokes/:ids
  def create
    ids = parse_ids
    channels = Channel.where(id: ids).to_a

    unless params[:confirm].to_s == "yes"
      redirect_to channels_path, alert: "revoke cancelled."
      return
    end

    if channels.empty?
      redirect_to channels_path, alert: "nothing to revoke."
      return
    end

    channels.each do |channel|
      DeleteChannelDataJob.perform_async(channel.id, channel.youtube_connection_id)
    end

    n = channels.length
    redirect_to channels_path,
                notice: "#{n} channel revoke#{'s' if n != 1} scheduled."
  end

  private

  def parse_ids
    params[:ids].to_s.split(",").reject(&:blank?).map(&:to_i).reject(&:zero?).uniq
  end

  # Return the subset of YoutubeConnection rows that would be orphaned
  # if this bulk revoke completes. A connection is orphaned when:
  #
  #   - Every Channel currently linked to it is in the revoke set, AND
  #   - No Videos under that connection survive after the cascade.
  #
  # The second condition is verified at modal render time. Channel
  # destroys nullify the connection FK on Video rows (Phase 7C
  # disconnect-lifecycle decision), so a video that is NOT under one
  # of the revoke targets but still references the connection
  # preserves the connection. The bulk-revoke modal surfaces this so
  # the user can see which Google grants will be revoked.
  def compute_orphan_connections(channels)
    revoke_channel_ids = channels.map(&:id)
    connection_ids = channels.map(&:youtube_connection_id).compact.uniq

    YoutubeConnection.where(id: connection_ids).select do |conn|
      remaining_channels = Channel.where(youtube_connection_id: conn.id)
                                  .where.not(id: revoke_channel_ids)
                                  .exists?
      next false if remaining_channels

      surviving_video_ids = Video.where(youtube_connection_id: conn.id)
                                 .where.not(channel_id: revoke_channel_ids)
                                 .exists?
      !surviving_video_ids
    end
  end
end
