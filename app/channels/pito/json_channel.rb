# frozen_string_literal: true

module Pito
  # The JSON mirror of a conversation's scrollback — the cable side of the
  # non-browser client surface (pito-tui et al.). Subscribes by BARE uuid
  # (no Turbo signed name needed: unlike the HTML stream, access here is
  # gated by AUTH, not by possession of a signed token), and receives the
  # messages the Broadcaster mirrors from its persisted-event choke points:
  #
  #   { type: "event.append"|"event.replace", event: Pito::Stream::EventJson }
  #
  # Guests are REJECTED outright: the web page withholds the scrollback from
  # anonymous visitors, and this channel must be no leakier. (Its consumer-less
  # predecessor, Pito::ChatChannel, let any anonymous socket subscribe to a
  # conversation's HTML stream by uuid — this replacement closes that.)
  class JsonChannel < ApplicationCable::Channel
    def subscribed
      reject and return unless connection.authenticated?

      conversation = ::Conversation.find_by(uuid: params[:uuid].to_s)
      reject and return unless conversation

      stream_from "pito:json:conversation:#{conversation.uuid}"
    end
  end
end
