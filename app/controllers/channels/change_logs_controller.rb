module Channels
  # Phase 7.5 §11g — Channel Change History View.
  #
  # Read-only paginated list of `ChannelChangeLog` rows for a single
  # channel. The audit table itself (Step 11a) is append-only at the
  # model layer (`readonly?` returns true once persisted); this
  # controller never mutates the table.
  #
  # HTML and JSON branches share the same scope + pagination math —
  # the jbuilder template owns the wire-envelope shape (Phase 21 list-
  # endpoint contract: `changes` array + `pagination` meta).
  #
  # Pagination follows the `NotificationsController` precedent: page
  # size 50, `@page = [params[:page].to_i, 1].max`. Out-of-range pages
  # render an empty body rather than 404.
  class ChangeLogsController < ApplicationController
    PER_PAGE = 50

    skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

    def index
      @channel = Channel.friendly.find(params[:channel_id])
      return if redirect_to_canonical_channel_slug!

      @page = [ params[:page].to_i, 1 ].max

      scope = @channel.channel_change_logs.order(changed_at: :desc)

      @total       = scope.count
      @total_pages = [ ((@total + PER_PAGE - 1) / PER_PAGE), 1 ].max
      @per_page    = PER_PAGE
      @logs        = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

      respond_to do |format|
        format.html { render :index }
        format.json { render :index }
      end
    end

    private

    # Per `FriendlyRedirect` precedent — issue a 301 when the request
    # used a non-canonical key (integer id, legacy slug). The nested
    # route uses `params[:channel_id]` rather than `params[:id]`, so
    # we cannot reuse the concern as-is; the logic is small enough to
    # inline.
    def redirect_to_canonical_channel_slug!
      return false unless request.get? || request.head?
      return false if params[:channel_id].to_s == @channel.to_param.to_s

      redirect_to channel_change_logs_path(@channel), status: :moved_permanently
      true
    end
  end
end
