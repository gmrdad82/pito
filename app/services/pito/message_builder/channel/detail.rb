# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload Hash for a channel-detail `:system` event
      # (`show channel @handle`). Mirrors Pito::MessageBuilder::Video::Detail:
      # a witty 50-variant intro (subject-shimmered title) above the card's left
      # column, then the Pito::Channel::DetailComponent (avatar · stats · shinies ·
      # kv-table). Not follow-up-able for now (the repliable surface is the
      # `:enhanced` linked-videos list).
      #
      # NAMESPACE: `Channel` here is the MessageBuilder sub-module; use ::Channel
      # for the model and Pito::Channel::* for the component.
      module Detail
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channel      [::Channel]     the channel record to render.
        # @param conversation [Conversation]  accepted for signature parity (unused
        #                                     until the card becomes follow-up-able).
        # @return [Hash] system event payload with body + html: true.
        def call(channel, conversation: nil)
          intro = Pito::Copy.render_html(
            "pito.copy.channels.detail_intro", { title: channel.title }, shimmer: [ :title ]
          )
          body = render_component(Pito::Channel::DetailComponent.new(channel: channel, intro: intro))
          html_payload(body: body)
        end
      end
    end
  end
end
