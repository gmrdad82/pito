# Phase 24 — per-channel `[revoke]` flow.
#
# Two-action controller mirroring the `DeletionsController` /
# `SyncsController` pattern: GET renders the wide-modal confirmation
# page (a server-rendered surface, not a JS overlay — `CLAUDE.md` hard
# rule against `data-turbo-confirm` and JS dialogs); POST consumes the
# `confirm=yes` form and enqueues `DeleteChannelDataJob` against the
# resolved channel.
#
# Yes/no boundary: the `confirm` param is `"yes"` (anything else is
# treated as cancel, per the project's external-boolean rule).
class ChannelRevokesController < ApplicationController
  include FriendlyRedirect

  # GET /channels/:id/revoke
  def show
    @channel = Channel.friendly.find(params[:id])
    return if redirect_to_canonical_slug!(@channel) { |c| revoke_channel_path(c) }

    @counts = ChannelRevokeCounts.for(@channel)
    @youtube_connection = @channel.youtube_connection
    @is_last_channel_on_connection = compute_last_channel?(@channel)

    render :show
  end

  # POST /channels/:id/revoke
  def create
    channel = Channel.friendly.find(params[:id])

    unless params[:confirm].to_s == "yes"
      redirect_to channel_path(channel), alert: "revoke cancelled."
      return
    end

    DeleteChannelDataJob.perform_async(channel.id, channel.youtube_connection_id)
    redirect_to channels_path, notice: "channel revoke scheduled."
  end

  private

  # True when this channel is the only channel currently linked to the
  # underlying YoutubeConnection. The modal renders a conditional
  # "Google grant will also be revoked" hint when true. The check is
  # only meaningful when the channel has a connection at all; nil
  # `youtube_connection_id` → false.
  def compute_last_channel?(channel)
    connection_id = channel.youtube_connection_id
    return false if connection_id.nil?

    Channel.where(youtube_connection_id: connection_id).count <= 1
  end
end
