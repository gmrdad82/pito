# frozen_string_literal: true

module Pito
  module Dispatch
    # The source context a verb handler runs against — the surface-agnostic half
    # of the uniform dispatch contract (plan-0.9.5 T8.10).
    #
    # `Pito::Dispatch::Router` builds one of these per invocation and passes it to
    # the verb's dispatch class as `call(kwargs:, context:)`. It carries exactly
    # what today's chat handlers read: the parsed +message+, the +conversation+,
    # the shift+tab +channel+ scope, the analytics +period+, the +follow_up+
    # context (present only on `#<handle>` replies), and the scrollback
    # +viewport_width+. The Router-bound arguments (segment selection / reply
    # ReplyBinding output) travel separately in `kwargs`, keeping "what the verb
    # was called WITH" distinct from "where the verb was called FROM".
    #
    # A free-chat invocation carries `follow_up: nil`; a reply invocation carries a
    # populated `Pito::Chat::FollowUpContext`. `follow_up?` is the predicate.
    Context = Data.define(:message, :conversation, :channel, :period, :follow_up, :viewport_width) do
      # Only +message+ and +conversation+ are required; the rest default so specs
      # and free-chat callers need not spell out every scope.
      def initialize(message:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil)
        super
      end

      # True when this verb was reached via a `#<handle>` follow-up reply.
      def follow_up?
        !follow_up.nil?
      end
    end
  end
end
