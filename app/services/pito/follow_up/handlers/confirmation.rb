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

        VALID_ACTIONS = %w[confirm cancel].freeze
        # Commands whose confirmed outcome kicks off background work and read
        # better as a neutral system progress line than the orange
        # confirmation-outcome card. (Cancel still renders the orange card.)
        SYSTEM_OUTCOME_ON_CONFIRM = %w[import_videos].freeze
        # Commands whose confirmed outcome is a finished, pito-voiced result that
        # reads better as the enhanced (pito-brand bar) line than the orange
        # confirmation-outcome card. (Cancel still renders the orange card.)
        ENHANCED_OUTCOME_ON_CONFIRM = %w[video_schedule video_publish video_unlist video_delete].freeze
        # Friendly synonyms → canonical action.
        ACTION_ALIASES = {
          "yes"     => "confirm",
          "y"       => "confirm",
          "ok"      => "confirm",
          "approve" => "confirm",
          "true"    => "confirm",
          "no"      => "cancel",
          "n"       => "cancel",
          "false"   => "cancel",
          "discard" => "cancel"
        }.freeze

        # @param event        [Event]        the source confirmation event.
        # @param rest         [String]       the text after `#<handle> ` — e.g. "confirm".
        # @param conversation [Conversation] the owning conversation (unused here but part of contract).
        # @return [Pito::FollowUp::Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil) # rubocop:disable Lint/UnusedMethodArgument
          action, _args = parse_rest(rest)
          action = ACTION_ALIASES.fetch(action, action)   # yes→confirm, no→cancel

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
            events: [ outcome_event(command, action, outcome_text) ]
          )
        end

        private

        # Build the appended outcome event. Most confirmations render the orange
        # confirmation-outcome card; a few (SYSTEM_OUTCOME_ON_CONFIRM) read better
        # as a neutral system progress line on confirm.
        def outcome_event(command, action, outcome_text)
          if action == "confirm" && SYSTEM_OUTCOME_ON_CONFIRM.include?(command)
            return { kind: :system, payload: { "text" => outcome_text } }
          end

          if action == "confirm" && ENHANCED_OUTCOME_ON_CONFIRM.include?(command)
            return { kind: :enhanced, payload: { "text" => outcome_text } }
          end

          {
            kind:    :confirmation_follow_up,
            payload: {
              command:      command,
              outcome:      action,
              outcome_text: outcome_text,
              resolved:     true
            }
          }
        end
      end
    end
  end
end
