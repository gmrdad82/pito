# frozen_string_literal: true

# GET /notifications → loads recent notifications and renders the sidebar
# overlay (Turbo Stream updating #pito-sidebar), mirroring how /resume works.
#
# Auth gating: inherits Sessions::AuthConcern from ApplicationController.
# No allow_anonymous — unauthenticated requests are redirected to root.
class NotificationsController < ApplicationController
  def index
    @notifications = Notification.panel_ordered

    respond_to do |format|
      format.turbo_stream { render "notifications/index" }
      format.html         { redirect_to root_path }
    end
  end

  # PATCH /notifications/:id { read: <bool> }
  # Toggles a notification's read state. The sidebar updates the row
  # optimistically. After persisting, broadcast the updated mini-status (unread
  # count) to pito:global so every open browser instance reflects the new count.
  def update
    notification = Notification.find(params[:id])
    read = ActiveModel::Type::Boolean.new.cast(params[:read])
    notification.update!(read_at: read ? Time.current : nil)

    # Cross-instance unread-count sync.
    Pito::Stream::Broadcaster.broadcast_global_mini_status

    head :no_content
  end
end
