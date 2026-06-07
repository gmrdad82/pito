# frozen_string_literal: true

module Pito
  module FollowUp
    # Base class for follow-up handlers.
    #
    # == Contract
    #
    # Subclasses MUST:
    #   - Call `self.target "some_id"` to declare the handler id (the string
    #     stored in event.payload["reply_target"]).
    #   - Call `self.mode :mutate` or `self.mode :append` to declare the
    #     processing mode (see below).
    #   - Override `#call(event:, rest:, conversation:)` and return a
    #     Pito::FollowUp::Result value.
    #
    # == Modes
    #
    # `:mutate`  — the handler transforms the source event in place.
    #              The controller creates NO echo and NO turn before enqueuing.
    #              FollowUpDispatchJob calls event.update! + replace_event.
    #              Example: theme preview/apply transforming the list message.
    #
    # `:append`  — the handler appends new events to the conversation.
    #              The controller creates an echo + turn BEFORE enqueuing
    #              (the job needs the turn to associate the new events).
    #              FollowUpDispatchJob persists result.events, broadcasts them,
    #              then consumes the source (reply_consumed: true) + replace_event.
    #              Example: confirmations producing a follow-up outcome message.
    #
    # == Rest-parser helper
    #
    # `parse_rest(rest)` splits the trailing string into `[action, args]` where
    # `action` is the first token (downcased) and `args` is everything after it
    # (stripped).  Useful for handlers that support multiple actions.
    #
    # == Auto-registration
    #
    # Defining a subclass automatically registers it in Pito::FollowUp::Registry
    # (via inherited hook), so no manual registration step is required.
    #
    # == Example
    #
    #   class Pito::FollowUp::Handlers::MyHandler < Pito::FollowUp::Handler
    #     self.target "my_handler"
    #     self.mode   :mutate
    #
    #     def call(event:, rest:, conversation:)
    #       action, _args = parse_rest(rest)
    #       case action
    #       when "do_it"
    #         Pito::FollowUp::Result::Mutation.new(
    #           kind: :system,
    #           payload: event.payload.merge("done" => true)
    #         )
    #       else
    #         Pito::FollowUp::Result::Error.new(
    #           message_key: "pito.follow_up.errors.unknown_action",
    #           message_args: { action: }
    #         )
    #       end
    #     end
    #   end
    class Handler
      # Class-level DSL ─────────────────────────────────────────────────────────

      class << self
        attr_reader :target_id, :handler_mode

        # Declare (or read) the action words this follow-up accepts, in the
        # order they should be suggested when the user types `#<handle> `.
        # Used by the suggestions engine to offer target-aware completions
        # (e.g. theme_list → preview/apply) instead of generic hashtag verbs.
        def actions(*list)
          if list.any?
            @handler_actions = list.flatten.map(&:to_s)
          else
            @handler_actions || []
          end
        end

        # Declare the handler's id (stored in reply_target).
        def target(id = nil)
          if id
            @target_id = id.to_s
          else
            @target_id
          end
        end

        # Declare the processing mode — :mutate or :append.
        def mode(m = nil)
          if m
            unless %i[mutate append].include?(m.to_sym)
              raise ArgumentError, "mode must be :mutate or :append, got: #{m.inspect}"
            end
            @handler_mode = m.to_sym
          else
            @handler_mode
          end
        end

        # Auto-register in Registry when a concrete subclass is defined.
        def inherited(subclass)
          super
          # Registration is deferred until the subclass body is fully evaluated
          # (the target/mode calls happen inside the class body after inherited).
          TracePoint.trace(:end) do |tp|
            if tp.self == subclass
              tp.disable
              Pito::FollowUp::Registry.register(subclass) if subclass.target_id
            end
          end
        end
      end

      # Instance interface ──────────────────────────────────────────────────────

      # Subclasses override this method.
      # @param event        [Event]        the source follow-up-able event.
      # @param rest         [String]       everything after `#<handle> `.
      # @param conversation [Conversation] the owning conversation.
      # @return [Pito::FollowUp::Result::Mutation | Append | Error]
      def call(event:, rest:, conversation:)
        raise NotImplementedError, "#{self.class}#call is not implemented"
      end

      private

      # Split `rest` into [action, args].
      # "preview tokyo-night" → ["preview", "tokyo-night"]
      # "confirm"            → ["confirm", ""]
      def parse_rest(rest)
        parts  = rest.to_s.strip.split(/\s+/, 2)
        action = parts[0].to_s.downcase
        args   = parts[1].to_s.strip
        [ action, args ]
      end
    end
  end
end
