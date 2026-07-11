# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for :ai answers carrying suggestion blocks.
      #
      #   #a7 apply      → run the FIRST suggestion's command
      #   #a7 apply 2    → run the second
      #
      # The suggested command executes through the unmodified Router — exactly
      # as if the owner typed it, including any confirmation the command itself
      # requires (an `update vid …` still asks before touching YouTube). The
      # source :ai message stays live (consume: false) so the owner can apply
      # its other suggestions afterwards.
      class AiMessage < Pito::FollowUp::Handler
        self.target "ai_message"

        def call(event:, rest:, conversation:, **)
          action, args = parse_rest(rest)
          unless action == "apply"
            return Result::Error.new(
              message_key:  "pito.follow_up.errors.unknown_action",
              message_args: { action: action.to_s }
            )
          end

          suggestions = Array(event.payload["blocks"]).select { |b| b["type"] == "suggestion" }
          index      = args.to_s[/\A\d+/]&.to_i || 1
          suggestion = index.positive? ? suggestions[index - 1] : nil
          if suggestion.nil?
            return Result::Error.new(
              message_key:  "pito.copy.ai.apply.missing",
              message_args: { index: index, count: suggestions.size }
            )
          end

          result = Pito::Dispatch::Router.call(input: suggestion["command"].to_s, conversation:)
          events = Pito::Dispatch::Finalizer.result_events(result)
          return Result::Error.new(message_key: "pito.copy.ai.errors.failed", message_args: {}) if events.empty?

          Result::Append.new(events:, consume: false)
        end
      end
    end
  end
end
