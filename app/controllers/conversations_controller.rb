class ConversationsController < ApplicationController
  # Chat shell for a specific conversation (/chat/:uuid).
  allow_anonymous :show

  # DELETE /chat/:uuid
  # Destroys the conversation and all dependent turns/events. Requires
  # authentication (no allow_anonymous). Responds 204 No Content on success.
  def destroy
    conversation = Conversation.find_by!(uuid: params[:uuid])
    conversation.destroy!
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
    @events = @authenticated ? @conversation.events.includes(:turn).order(:position) : Event.none
  end

  # GET /resume — re-render the conversations sidebar (same Turbo Stream as the
  # /resume command). Used to restore the panel after a reload when the client's
  # localStorage says it was open. Auth required (not allow_anonymous).
  def resume
    respond_to do |format|
      format.turbo_stream do
        render partial: "chat/resume_sidebar",
               formats: [ :turbo_stream ],
               locals:  {
                 groups:       Conversation.recency_groups,
                 current_uuid: params[:uuid].presence
               }
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

  def conversation_params
    # Slice to the attributes we accept BEFORE permitting, so the route param
    # (:uuid) and any param-wrapper duplicate (:conversation) are never seen by
    # `permit` — avoids spurious "Unpermitted parameters" log noise. The client
    # sends a top-level { draft: … } / { title: … }; both are picked up here.
    params.slice(:title, :draft, :scope_channel, :stats_period)
          .permit(:title, :draft, :scope_channel, :stats_period)
  end
end
