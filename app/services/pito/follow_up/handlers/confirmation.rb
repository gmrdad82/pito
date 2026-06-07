# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for confirmation events.
      #
      # Replaces the old ConfirmationDispatchJob mutate-in-place flow.  When the
      # user replies `#<handle> confirm` or `#<handle> cancel` to a confirmation
      # event that was stamped by the follow-up engine, this handler:
      #
      #   1. Parses the action from `rest` — must be "confirm" or "cancel";
      #      anything else returns a Result::Error.
      #   2. Delegates to Pito::Confirmation::Executor.<action>(command, payload)
      #      to get the outcome_text (may raise StandardError — caught here).
      #   3. Returns Result::Append with a single `confirmation_follow_up` event
      #      carrying { command:, outcome:, outcome_text:, resolved: true }.
      #
      # The engine job (FollowUpDispatchJob) then:
      #   - Persists the appended event on the echo's turn + broadcasts it.
      #   - Sets reply_consumed:true on the original confirmation + broadcasts replace.
      #
      # Mode: :append — the controller creates an echo + turn before enqueuing.
      class Confirmation < Pito::FollowUp::Handler
        self.target "confirmation"
        self.mode   :append
        self.actions "confirm", "cancel"

        VALID_ACTIONS = %w[confirm cancel].freeze

        # @param event        [Event]        the source confirmation event.
        # @param rest         [String]       the text after `#<handle> ` — e.g. "confirm".
        # @param conversation [Conversation] the owning conversation (unused here but part of contract).
        # @return [Pito::FollowUp::Result::Append | Result::Error]
        def call(event:, rest:, conversation:)
          action, _args = parse_rest(rest)

          unless VALID_ACTIONS.include?(action)
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.confirmation.errors.invalid_action",
              message_args: { action: action }
            )
          end

          payload = event.payload.with_indifferent_access
          command = payload[:command].to_s

          outcome_text =
            begin
              Pito::Confirmation::Executor.public_send(action, command, payload)
            rescue StandardError
              Pito::Copy.render("pito.copy.confirmation.execution_failed")
            end

          Pito::FollowUp::Result::Append.new(
            events: [
              {
                kind:    "confirmation_follow_up",
                payload: {
                  command:      command,
                  outcome:      action,
                  outcome_text: outcome_text,
                  resolved:     true
                }
              }
            ]
          )
        end
      end
    end
  end
end
