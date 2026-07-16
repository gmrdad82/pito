class ConversationsController < ApplicationController
  # Chat shell for a specific conversation (/chat/:uuid).
  allow_anonymous :show

  # DELETE /chat/:uuid
  # ASYNC delete: marks the conversation in-flight (deleting_at), swaps its sidebar
  # row to the shimmering-dots placeholder everywhere (pito:global), and hands the
  # potentially-slow turns/events cascade to DeleteConversationJob. Requires
  # authentication (no allow_anonymous). Responds 204 No Content.
  def destroy
    conversation = Conversation.find_by!(uuid: params[:uuid])
    # Shared mark-and-enqueue path — the SAME service the nightly auto-purge uses
    # (Conversation::RequestDeletion), so the two never drift.
    Conversation::RequestDeletion.call(conversation: conversation)
    head :no_content
  end

  # PATCH /chat/:uuid
  # Updates a conversation's title. Requires authentication (no allow_anonymous).
  # Blank titles are rejected with 422 — the client should keep the old title.
  # On success, responds with a Turbo Stream that replaces the sidebar row.

  def show
    @conversation = Conversation.find_by!(uuid: params[:uuid])
    @authenticated = Current.session.present?

    # SECURITY: unauthenticated visitors may load this page only to /login — they
    # must NOT see the conversation's contents. Withhold the scrollback here; the
    # view likewise withholds the typed-command history, draft, and title.
    @events      = @authenticated ? @conversation.events.includes(:turn).order(:position) : Event.none
    @event_count = @authenticated ? @conversation.context_event_count : 0

    respond_to do |format|
      format.html do
        # L2 snapshot: the assembled scrollback serves as ONE
        # cache read; misses rebuild from the L1 fragment layer. Broadcaster
        # chokepoints bust it on every scrollback-visible change. Authenticated only.
        @scrollback_html =
          if @authenticated
            Pito::Stream::ScrollbackCache.fetch(@conversation) do
              Pito::Stream::ScrollbackCache.assemble(@events.to_a)
            end
          else
            ""
          end
        render :show
      end

      # The JSON backfill for non-browser clients (pito-tui): the same events,
      # via the same EventJson shape the live Pito::JsonChannel mirror uses —
      # backfill and stream can never drift. Where the HTML page withholds
      # silently (anonymous visitors still get the shell to /login in), JSON
      # is explicit: 401.
      format.json do
        if @authenticated
          count = @conversation.context_event_count
          render json: {
            conversation: {
              uuid:         @conversation.uuid,
              title:        @conversation.title,
              display_name: @conversation.display_name,
              created_at:   @conversation.created_at.iso8601,
              # The context meter, server-computed — pct is the exact
              # number the web meter draws (ContextMeterComponent math).
              context: {
                pct:       Pito::Shell::ContextMeterComponent.pct(count),
                count:     count,
                threshold: Pito::Shell::ContextMeterComponent::THRESHOLD
              },
              # The shift+tab / shift+space cycler state (TUI seeds its
              # cyclers from these; additive — older clients ignore them).
              scope: {
                channel: @conversation.scope_channel,
                period:  @conversation.stats_period
              }
            },
            # The cycler's option set: @all first, then the connected
            # channels' handles in stable alphabetical order.
            channels: ([ "@all" ] + Channel.order(:handle).pluck(:handle)
                                            .map { |h| h.start_with?("@") ? h : "@#{h}" }).uniq,
            # Mini-status data for non-browser clients (the nickname/"me"
            # concept was fat-cut 2026-07-12 — identity is the build tag now).
            notifications: { unread: Notification.unread.count },
            events: @events.map { |e| Pito::Stream::EventJson.call(e) }
          }
        else
          render json: {
            error:   "unauthenticated",
            message: Pito::Copy.render("pito.copy.auth.mandatories")
          }, status: :unauthorized
        end
      end
    end
  end

  # GET /resume — re-render the conversations sidebar (same Turbo Stream as the
  # /resume command). Used to restore the panel after a reload when the client's
  # localStorage says it was open. Auth required (not allow_anonymous).
  def resume
    respond_to do |format|
      format.turbo_stream do
        # Paginated (`?after=<opaque cursor>`) → APPEND the next page's rows
        # into the sidebar's more-container and REPLACE the pager sentinel —
        # the same shape NotificationsController#index answers. Bare → the
        # full panel (page 1 + sentinel).
        if params[:after].present?
          @page = Conversation.recency_page(after: params[:after], limit: resume_page_limit)
          @ai_uuids = ai_thread_uuids(@page[:older])
          render "conversations/resume_append"
        else
          page = Conversation.recency_page(limit: resume_page_limit)
          render partial: "chat/resume_sidebar",
                 formats: [ :turbo_stream ],
                 locals:  {
                   groups:       page.slice(:recent, :older),
                   next_cursor:  page[:next_cursor],
                   current_uuid: params[:uuid].presence
                 }
        end
      end

      # The conversation picker for non-browser clients (pito-tui): the same
      # keyset-paged rows the sidebar renders, as data. `limit` (the tui's
      # viewport row count, owner 2026-07-15) is honored via resume_page_limit
      # — clamped to the :resume tool's max_page_size; absent/invalid falls
      # back to Conversation::SIDEBAR_PAGE_SIZE. Auth is enforced by the
      # concern (anonymous JSON → 401 before this runs).
      format.json do
        if params[:after].present?
          # Follow-up page — flat `rows:` (everything past page 1 is "older"
          # by construction); me/notifications only ride on page 1.
          page = Conversation.recency_page(after: params[:after], limit: resume_page_limit)
          ai_uuids = ai_thread_uuids(page[:older])
          render json: {
            rows:        page[:older].map { |c| conversation_json_row(c, ai_uuids) },
            next_cursor: page[:next_cursor]
          }
        else
          # Page 1 — same shape as before (recent/older + me/notifications),
          # rows capped at resume_page_limit (default SIDEBAR_PAGE_SIZE) with
          # a next_cursor for more.
          page = Conversation.recency_page(limit: resume_page_limit)
          ai_uuids = ai_thread_uuids(page[:recent] + page[:older])
          render json: {
            recent:        page[:recent].map { |c| conversation_json_row(c, ai_uuids) },
            older:         page[:older].map { |c| conversation_json_row(c, ai_uuids) },
            next_cursor:   page[:next_cursor],
            notifications: { unread: Notification.unread.count }
          }
        end
      end

      format.html { redirect_to root_path }
    end
  end

  def update
    @conversation = Conversation.find_by!(uuid: params[:uuid])

    # Scope-save path: shift+tab (scope_channel) / shift+space (stats_period)
    # persistence. Quiet background save — no Turbo Stream, just 204 No Content,
    # so a reload restores the conversation's last channel/period.
    scope_attrs = conversation_params.slice(:scope_channel, :stats_period)
    if scope_attrs.present? && !conversation_params.key?(:title)
      @conversation.update!(scope_attrs)
      head :no_content
      return
    end

    # Draft-save path: params contain :draft but NOT :title.
    # Quiet background autosave — no Turbo Stream, just 204 No Content.
    if conversation_params.key?(:draft) && !conversation_params.key?(:title)
      @conversation.update!(draft: conversation_params[:draft].presence)
      head :no_content
      return
    end

    # Rename path: params contain :title (existing behaviour — keep intact).
    new_title = conversation_params[:title]

    if new_title.blank?
      render json: { error: I18n.t("pito.chat.conversations.errors.title_blank") }, status: :unprocessable_content
      return
    end

    # Shared rename path (update + chatbox-name + global-sidebar-row broadcasts) —
    # the same service the `/rename` slash command uses, so they never drift.
    Conversation::Rename.call(conversation: @conversation, title: new_title)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "conversation_row_#{@conversation.uuid}",
          partial: "conversations/row",
          locals: {
            conversation: @conversation,
            current:      false,
            timestamp:    Pito::Formatter::CompactTimeAgo.call(
              @conversation.events.maximum(:created_at) || @conversation.created_at
            )
          }
        )
      end
      format.json { render json: { title: @conversation.title }, status: :ok }
    end
  end

  private

  # The pito-tui viewport-driven `limit` for /resume's cursor feed, clamped to
  # the :resume tool's max_page_size (owner 2026-07-15); see
  # ApplicationController#client_page_limit for the shared mechanism.
  def resume_page_limit
    client_page_limit(tool: :resume, default: Conversation::SIDEBAR_PAGE_SIZE)
  end

  # Which of these conversations carry :ai messages — ONE query for the whole
  # page, so appended rows wear the AI badge without a per-row EXISTS.
  def ai_thread_uuids(conversations)
    Conversation.joins(:events)
                .where(uuid: conversations.map(&:uuid), events: { kind: "ai" })
                .distinct.pluck(:uuid).to_set
  end

  # A /resume.json row: the same fields the sidebar shows, plus `ai:` —
  # true when this conversation has an :ai event, sourced from the caller's
  # ONE batched ai_thread_uuids lookup (never a per-row query).
  def conversation_json_row(conversation, ai_uuids)
    {
      uuid:             conversation.uuid,
      title:            conversation.title,
      display_name:     conversation.display_name,
      last_activity_at: conversation.last_activity_at&.to_time&.iso8601,
      ai:               ai_uuids.include?(conversation.uuid)
    }
  end


  def conversation_params
    # Slice to the attributes we accept BEFORE permitting, so the route param
    # (:uuid) and any param-wrapper duplicate (:conversation) are never seen by
    # `permit` — avoids spurious "Unpermitted parameters" log noise. The client
    # sends a top-level { draft: … } / { title: … }; both are picked up here.
    params.slice(:title, :draft, :scope_channel, :stats_period)
          .permit(:title, :draft, :scope_channel, :stats_period)
  end
end
