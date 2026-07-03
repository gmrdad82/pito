# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for an `analyze` message (reply_target: "analyze_message").
      #
      # Replying `#<handle> with <metrics>` / `#<handle> without <metrics>` (snake_case
      # names, comma/space separated) MUTATES that message IN PLACE — re-renders the
      # 0/1 cells with the accumulated selection, from the PERSISTED scaffold map (no
      # re-fetch). The handle is NOT consumed, so the owner can keep refining.
      #
      # Accumulation: `without X` excludes X; `with X` re-includes it (or extends an
      # active whitelist). See Pito::Analytics::MetricSelection.
      #
      # NAMESPACE: use `::Video`/`::Game` for models; `Pito::*` for services.
      class AnalyzeMessage < Pito::FollowUp::Handler
        self.target "analyze_message"

        def call(event:, rest:, conversation:, **)
          action, args = parse_rest(rest)
          return invalid_action(action) unless %w[with without].include?(action)

          metrics = Pito::Analytics::MetricSelection.symbolize(args.to_s.split(/[\s,]+/))
          return no_metrics if metrics.empty?

          with, without = accumulate(event, action, metrics)
          payload = Pito::MessageBuilder::Analyze::Message.rerender(event, with:, without:)
          Pito::FollowUp::Result::Mutation.new(kind: event.kind.to_sym, payload:)
        end

        private

        # Fold the reply into the message's current selection.
        #   without X → exclude X (drop from any whitelist)
        #   with X    → re-include X (un-exclude; extend an active whitelist)
        def accumulate(event, action, metrics)
          marker  = event.payload.fetch("analyze")
          with    = Pito::Analytics::MetricSelection.symbolize(marker["with"])
          without = Pito::Analytics::MetricSelection.symbolize(marker["without"])

          case action
          when "with"
            metrics.each { |m| without.delete(m); with << m if with.any? }
          when "without"
            metrics.each { |m| with.delete(m); without |= [ m ] }
          end
          [ with.uniq, without.uniq ]
        end

        def invalid_action(action)
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.analyze_message.errors.invalid_action",
            message_args: { action: }
          )
        end

        def no_metrics
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.analyze_message.errors.no_metrics",
            message_args: {}
          )
        end
      end
    end
  end
end
