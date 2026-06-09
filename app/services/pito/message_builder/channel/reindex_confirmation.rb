# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload for a "reindex this channel?" confirmation.
      #
      # Emitted when the user replies `#<handle> reindex @<channel_handle>` to a
      # channel-list event. The executor branch (`channel_reindex` in
      # Pito::Confirmation::Executor) enqueues VideoVoyageIndexJob for every video
      # in the channel on confirm (async batch — so we render a "queued" outcome,
      # not "done").
      module ReindexConfirmation
        module_function

        # @param channel      [::Channel]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(channel, conversation:)
          handle = channel.handle.presence || channel.title.to_s

          payload = {
            "command"        => "channel_reindex",
            "body"           => Pito::Copy.render("pito.copy.channels.reindex_confirm", { handle: handle }),
            "html"           => false,
            "channel_id"     => channel.id,
            "channel_handle" => handle
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
