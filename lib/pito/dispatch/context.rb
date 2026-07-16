# frozen_string_literal: true

module Pito
  module Dispatch
    # The source context a tool handler runs against — the surface-agnostic half
    # of the uniform dispatch contract.
    #
    # `Pito::Dispatch::Router` builds one of these per invocation and passes it to
    # the tool's dispatch class as `call(kwargs:, context:)`. It carries exactly
    # what today's chat handlers read: the parsed +message+, the +conversation+,
    # the shift+tab +channel+ scope, the analytics +period+, the +follow_up+
    # context (present only on `#<handle>` replies), and the scrollback
    # +viewport_width+. The Router-bound arguments (segment selection / reply
    # ReplyBinding output) travel separately in `kwargs`, keeping "what the tool
    # was called WITH" distinct from "where the tool was called FROM".
    #
    # A free-chat invocation carries `follow_up: nil`; a reply invocation carries a
    # populated `Pito::Chat::FollowUpContext`. `follow_up?` is the predicate.
    #
    # `nl_eligible` (default true) is distinct from `follow_up` — see
    # Pito::Dispatch::Router's class header. False only for a handful of
    # Pito::FollowUp::Handlers::* reconstructed re-dispatches; read by handlers
    # as `nl_eligible?` (Pito::Chat::Handler) to decide whether a body they
    # can't resolve is allowed to soft-fail into the NL gate.
    Context = Data.define(:message, :conversation, :channel, :period, :follow_up, :viewport_width, :nl_eligible) do
      # Only +message+ and +conversation+ are required; the rest default so specs
      # and free-chat callers need not spell out every scope.
      def initialize(message:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil, nl_eligible: true)
        super
      end

      # True when this tool was reached via a `#<handle>` follow-up reply.
      def follow_up?
        !follow_up.nil?
      end
    end
  end
end
