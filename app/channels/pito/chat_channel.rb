# frozen_string_literal: true

module Pito
  class ChatChannel < ApplicationCable::Channel
    def subscribed
      stream_from "pito:conversation:#{params[:conversation_id]}"
    end
  end
end
