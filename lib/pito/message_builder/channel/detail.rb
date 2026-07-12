# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload Hash for a channel-detail `:system` event
      # (`show channel @handle`). Mirrors Pito::MessageBuilder::Video::Detail:
      # a witty 50-variant intro (subject-shimmered title) above the card's left
      # column, then the Pito::Channel::DetailComponent (avatar · stats · shinies ·
      # kv-table). Stamped follow-up-able (reply_target: "channel_detail") so the
      # user can reply `#<handle> visit channel` or `#<handle> visit studio`.
      #
      # NAMESPACE: `Channel` here is the MessageBuilder sub-module; use ::Channel
      # for the model and Pito::Channel::* for the component.
      module Detail
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channel      [::Channel]     the channel record to render.
        # @param conversation [Conversation]  used to generate the reply handle.
        # @return [Hash] system event payload with body, html: true, and follow-up fields.
        def call(channel, conversation: nil)
          intro = Pito::Copy.render_html(
            "pito.copy.channels.detail_intro", { title: channel.title }, shimmer: [ :title ]
          )
          body    = render_component(Pito::Channel::DetailComponent.new(channel: channel, intro: intro))
          payload = html_payload(body: body, channel_id: channel.id)

          Pito::FollowUp.make_followupable!(payload, target: "channel_detail", conversation: conversation) if conversation

          payload
        end
      end
    end
  end
end
