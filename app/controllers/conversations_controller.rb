class ConversationsController < ApplicationController
  # Chat shell for a specific conversation (/chat/:uuid).
  allow_anonymous :show

  def show
    @conversation = Conversation.find_by!(uuid: params[:uuid])
    @events = @conversation.events.includes(:turn).order(:position)
  end
end
