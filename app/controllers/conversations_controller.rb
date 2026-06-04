class ConversationsController < ApplicationController
  # Chat shell for a specific conversation (/chat/:uuid).
  allow_anonymous :show

  # PATCH /chat/:uuid
  # Updates a conversation's title. Requires authentication (no allow_anonymous).
  # Blank titles are rejected with 422 — the client should keep the old title.
  # On success, responds with a Turbo Stream that replaces the sidebar row.

  def show
    @conversation = Conversation.find_by!(uuid: params[:uuid])
    @events = @conversation.events.includes(:turn).order(:position)
  end

  def update
    @conversation = Conversation.find_by!(uuid: params[:uuid])

    new_title = conversation_params[:title]

    if new_title.blank?
      render json: { error: "title cannot be blank" }, status: :unprocessable_entity
      return
    end

    @conversation.update!(title: new_title)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "conversation_row_#{@conversation.uuid}",
          partial: "conversations/row",
          locals: {
            conversation: @conversation,
            current:      false,
            timestamp:    nil
          }
        )
      end
      format.json { render json: { title: @conversation.title }, status: :ok }
    end
  end

  private

  def conversation_params
    params.permit(:title)
  end
end
