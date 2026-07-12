# frozen_string_literal: true

module Pito
  module Chat
    # The follow-up side of a tool invocation.
    #
    # When a user replies `#<handle> <tool> <rest>`, the SAME tool handler that
    # serves the free-chat `<tool> <rest>` runs — only the entry point differs.
    # This value carries what the follow-up path needs that a free-chat message
    # doesn't have:
    #
    #   - +source_event+ — the live event the user replied to (its `reply_target`
    #     decides the resolution scope: a list's rows, or a detail card's entity).
    #   - +rest+         — the trailing text after `#<handle> <tool> ` (e.g. "5"),
    #     same as the args a free-chat message would carry after the tool.
    #   - +bound+        — kwargs pre-resolved from the tool's declared
    #     `reply.targets.<target>.ref/args` paths in config/pito/tools.yml, via
    #     Pito::Dispatch::ReplyBinding (populated by ToolDelegator).
    #     Empty `{}` for free-chat construction and any target that
    #     declares no ref/args. Handlers do their OWN extraction for now; the
    #     Router is what makes these bound kwargs authoritative-in-effect.
    #
    # A handler reads `follow_up?` to know it was reached via a reply and
    # resolves its reference from this context instead of `message.raw`.
    FollowUpContext = Data.define(:source_event, :rest, :bound) do
      # `bound` defaults to {} so free-chat callers and specs that only need the
      # source event + rest need not pass it; only ToolDelegator populates it.
      def initialize(source_event:, rest:, bound: {})
        super(source_event:, rest:, bound:)
      end
    end
  end
end
