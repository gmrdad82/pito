# frozen_string_literal: true

module Pito
  module FollowUp
    # Adapts a verb handler's `Pito::Chat::Result` into a `Pito::FollowUp::Result`.
    # This is what lets ONE verb handler serve both entry
    # points: the follow-up dispatch runs the same handler and wraps its chat
    # result for the follow-up pipeline.
    #
    #   Chat::Result::Ok(events:)              → FollowUp::Result::Append(events:)
    #   Chat::Result::Error(message_key:, ...) → FollowUp::Result::Error(...)
    #
    # Event kinds pass through untouched — chat emits Symbols (`:system` /
    # `:enhanced` / `:confirmation`) and `Event` normalises symbol→string on save
    # (`normalizes :kind`), so symbols stay idiomatic at the call site. A
    # Confirmable verb needs no special case — its Ok already carries a
    # `confirmation` event, which flows straight through into the Append.
    module ChatResultAdapter
      module_function

      # @param result [Pito::Chat::Result::Ok, Pito::Chat::Result::Error]
      # @return [Pito::FollowUp::Result::Append, Pito::FollowUp::Result::Error]
      def call(result)
        case result
        when Pito::Chat::Result::Ok
          # Forward consume: a "soft" Ok (e.g. a not-found) carries consume: false
          # so the replied-to source list stays repliable for a retry.
          Pito::FollowUp::Result::Append.new(events: result.events, consume: result.consume)
        when Pito::Chat::Result::Error
          Pito::FollowUp::Result::Error.new(
            message_key:  result.message_key,
            message_args: result.message_args
          )
        else
          raise ArgumentError, "ChatResultAdapter cannot adapt #{result.class}"
        end
      end
    end
  end
end
