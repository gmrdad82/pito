class StatusBarChannel < ApplicationCable::Channel
  def subscribed
    stream_from "pito:status_bar"
  end
end
