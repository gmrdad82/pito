# frozen_string_literal: true

module Pito
  module FollowUp
    # Delegates a `#<handle> <verb> <rest>` reply to the SAME chat verb handler
    # that serves `<verb> <rest>` in free chat.
    #
    # A follow-up handler (game_list, game_detail, …) becomes a thin shim: it
    # passes the live source event + the reply's `rest` here. We reconstruct the
    # chat invocation, run it through `Chat::Dispatcher` with a `FollowUpContext`
    # attached (so resolution can scope to the source list's rows or read the
    # source card's entity), then adapt the chat result into a follow-up
    # result. One code path builds + sends; no duplication.
    #
    #   VerbDelegator.call(source_event: ev, rest: "show 5", conversation: c)
    #   # → runs Chat::Handlers::Show with follow_up context → FollowUp::Result::Append
    #
    # GATING: the verb must be one of the source event's allowed reply
    # actions (the `reply_target`'s declared `actions`, the canonical matrix). A
    # disallowed verb is rejected with that target's `invalid_action` copy — never
    # delegated. (An empty/unknown action list means "not gated".)
    module VerbDelegator
      module_function

      # @param source_event   [Event]        the live event being replied to.
      # @param rest            [String]       text after `#<handle> ` (e.g. "show 5", "rm").
      # @param conversation    [Conversation]
      # @param channel         [String, nil]  shift+tab channel scope, if any.
      # @param period          [String, nil]  analytics window (e.g. "28d"), if any.
      # @param viewport_width  [Integer, String, nil] scrollback width for list auto-fill.
      # @return [Pito::FollowUp::Result::Append, Pito::FollowUp::Result::Error]
      def call(source_event:, rest:, conversation:, channel: nil, period: nil, viewport_width: nil)
        input = rest.to_s.strip
        verb  = input[/\A\S+/].to_s.downcase

        reply_target = source_event.payload.to_h.with_indifferent_access[:reply_target].to_s
        allowed      = Pito::FollowUp::Registry.actions_for(reply_target).map(&:to_s)
        if allowed.any? && !allowed.include?(verb)
          return Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.#{reply_target}.errors.invalid_action",
            message_args: { action: verb }
          )
        end

        args    = input.sub(/\A\S+\s*/, "") # everything after the verb word

        # Consult the declarative reply-branch paths (verbs.yml
        # reply.targets.<target>.ref/args) via Pito::Dispatch::ReplyBinding, and
        # thread the resolved kwargs onto the follow-up context (plan-0.9.5 T8.7).
        # P2: the handlers still do their own extraction — `bound` is advisory,
        # so behaviour is byte-identical (the frozen matrices prove it); the P3
        # Router is what makes these kwargs authoritative-in-effect.
        binding = Pito::Dispatch::ReplyBinding.bind(
          verb:, target: reply_target, rest: args, source_event:, conversation:
        )
        context = Pito::Chat::FollowUpContext.new(source_event:, rest: args, bound: binding.kwargs)
        result  = Pito::Chat::Dispatcher.call(
          input:          input,
          conversation:   conversation,
          channel:        channel,
          period:         period,
          viewport_width: viewport_width,
          follow_up:      context
        )

        adapted = Pito::FollowUp::ChatResultAdapter.call(result)

        # link and unlink are repeatable: the source card must NOT be consumed
        # so the user can keep linking/unlinking additional targets.
        if %w[link unlink].include?(verb) && adapted.is_a?(Pito::FollowUp::Result::Append)
          adapted = Pito::FollowUp::Result::Append.new(events: adapted.events, consume: false)
        end

        adapted
      end
    end
  end
end
