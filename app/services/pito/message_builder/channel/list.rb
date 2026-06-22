# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload for the channel list message.
      #
      # Renders a Pito::Channel::ListComponent for the connected channels and
      # wraps it with a plain-text intro line. Stamped follow-up-able
      # (reply_target: "channel_list") so the user can reply
      # `#<handle> visit @<handle>` to open a channel page.
      #
      # NOTE: The caller is responsible for checking channels.empty? and returning
      # an appropriate empty-state before calling this builder.
      module List
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channels     [ActiveRecord::Relation | Array<::Channel>] non-empty, pre-fetched.
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] string-keyed payload with body, html: true, and follow-up fields.
        def call(channels, conversation:)
          intro = Pito::Copy.render_html(
            "pito.copy.channels.list_intro",
            { count: channels.size, noun: "channels" },
            shimmer: [ :count, :noun ]
          )
          strip_html = render_component(Pito::Channel::ListComponent.new(channels:))

          payload = html_payload(body: "#{intro}\n#{strip_html}")
          Pito::FollowUp.make_followupable!(payload, target: "channel_list", conversation: conversation)
          payload
        end
      end
    end
  end
end
