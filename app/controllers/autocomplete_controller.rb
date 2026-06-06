# frozen_string_literal: true

class AutocompleteController < ApplicationController
  allow_anonymous :create

  def create
    input        = params[:input].to_s
    cursor       = params[:cursor].present? ? params[:cursor].to_i : input.length
    conversation = params[:conversation].present? ? Conversation.find_by(uuid: params[:conversation]) : nil
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
