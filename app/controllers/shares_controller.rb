# frozen_string_literal: true

# SharesController — serves public, unauthenticated share pages.
#
# GET /share/:uuid
#   - Load the Share by uuid.
#   - If missing/revoked: render the :gone view (404).
#   - If live: load the conversation + event and render the :show view.
#
# POST /share/:uuid/unfold
#   - If the share is live: redirect to the parent conversation (/chat/:uuid).
#   - If missing/revoked: render the :gone view (404).
class SharesController < ApplicationController
  layout "share"

  allow_anonymous :show
  allow_anonymous :unfold

  def show
    @share = Share.find_by(uuid: params[:uuid])

    if @share.nil?
      render :gone, status: :not_found
      return
    end

    @conversation = @share.conversation
    @event        = @share.event
    # Cached intro + shared event + outro (0.9.0 Phase 7). The Share row lookup
    # above is the revocation gate — only live shares reach the cache.
    @scrollback_html = Pito::Share::PageCache.fetch(@share)
  end

  def unfold
    share = Share.find_by(uuid: params[:uuid])

    if share
      redirect_to conversation_path(share.conversation), allow_other_host: false
    else
      render :gone, status: :not_found
    end
  end
end
