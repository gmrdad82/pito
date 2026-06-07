# frozen_string_literal: true

class SuggestionsController < ApplicationController
  allow_anonymous :create

  def create
    input  = params[:input].to_s
    cursor = params[:cursor].present? ? params[:cursor].to_i : input.length
    # The chatbox posts the conversation as `uuid` (matching the rest of the
    # app); accept `conversation` too for back-compat. Without this the engine
    # can't resolve a #handle to its follow-up target and falls back to the
    # generic hashtag verbs (the "add subscribers" bug).
    uuid          = params[:uuid].presence || params[:conversation].presence
    conversation  = uuid ? Conversation.find_by(uuid: uuid) : nil
    authenticated = Current.session.present?

    result = Pito::Suggestions::Engine.call(
      input:,
      cursor:,
      conversation:,
      authenticated:
    )

    render json: result
  end
end
