# frozen_string_literal: true

# GET /notifications → loads recent notifications and renders the sidebar
# overlay (Turbo Stream updating #pito-sidebar), mirroring how /resume works.
# GET /notifications.json → the same keyset page as data, for non-browser
# clients (pito-tui).
#
# Auth gating: inherits Sessions::AuthConcern from ApplicationController.
# No allow_anonymous — unauthenticated requests are redirected to root (HTML)
# or get an explicit 401 (JSON).
class NotificationsController < ApplicationController
  # Bare (`?after` absent) → full panel into #pito-sidebar (first PAGE_SIZE rows
  # + a pager sentinel). Paginated (`?after=<opaque cursor>`) → a Turbo Stream
  # that APPENDS the next page's rows and REPLACES the sentinel. Keyset/cursor
  # paging lives in Notification.panel_page; the cursor token is opaque.
  def index
    @notifications, @next_cursor = Notification.panel_page(
      after: params[:after],
      limit: client_page_limit(tool: :notifications, default: Notification::PAGE_SIZE)
    )
    @append = params[:after].present?

    respond_to do |format|
      format.turbo_stream { render "notifications/index" }
      format.html         { redirect_to root_path }

      # The notifications panel for non-browser clients (pito-tui): the same
      # keyset page the turbo-stream branch renders, as data. `limit` (the
      # tui's viewport row count, owner 2026-07-15) is honored via
      # client_page_limit — clamped to the :notifications tool's
      # max_page_size; absent/invalid falls back to Notification::PAGE_SIZE.
      # Auth is enforced by the concern (anonymous JSON → 401 before this runs).
      format.json do
        render json: {
          rows: @notifications.map { |n|
            {
              id:         n.id,
              message:    n.message,
              read:       n.read?,
              created_at: n.created_at.iso8601
            }
          },
          next_cursor: @next_cursor
        }
      end
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
