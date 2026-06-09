# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Sync
      # Builds the payload for an "import new videos from <scope>?" confirmation.
      # The executor branch (`import_videos` in Pito::Confirmation::Executor) enqueues
      # ChatImportVideosJob on confirm, which runs a newer-only YouTube import and
      # broadcasts a summary ("Imported N new videos on @chan").
      module ImportVideosConfirmation
        module_function

        # @param scope_label  [String]         display label (e.g. "@pito" or "all channels")
        # @param channel_ids  [Array<Integer>] resolved channel ids; empty = all
        # @param conversation [Conversation]
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(scope_label, channel_ids:, conversation:)
          payload = {
            "command"         => "import_videos",
            "body"            => Pito::Copy.render("pito.copy.import_videos.confirm", { scope: scope_label }),
            "html"            => false,
            "scope_label"     => scope_label,
            "channel_ids"     => channel_ids,
            "conversation_id" => conversation.id
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
