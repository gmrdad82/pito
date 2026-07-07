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
    #   - Override `#call(event:, rest:, conversation:)` and return a
    #     Pito::FollowUp::Result value.
    #
    # == Mode and availability
    #
    # Reply mode (:mutate or :append) and the set of accepted action tokens are
    # declared in config/pito/verbs.yml and read at runtime via
    # Pito::Dispatch::Matrix.  Handlers do NOT declare mode or actions in Ruby —
    # verbs.yml is the sole source of truth.
    #
    # `:mutate`  — the handler transforms the source event in place.
    #              The controller creates NO echo and NO turn before enqueuing.
    #              FollowUpDispatchJob calls event.update! + replace_event.
    #
    # `:append`  — the handler appends new events to the conversation.
    #              The controller creates an echo + turn BEFORE enqueuing.
    #              FollowUpDispatchJob persists result.events, broadcasts them,
    #              then consumes the source (reply_consumed: true) + replace_event.
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
        attr_reader :target_id

        # Declare the handler's id (stored in reply_target).
        def target(id = nil)
          if id
            @target_id = id.to_s
          else
            @target_id
          end
        end

        # Mark this handler as internal — it is never user-facing.
        # Internal handlers:
        #   - emit no #hashtag handle (no reply_handle in the visit payload)
        #   - are excluded from #help and the hashtag suggestions palette
        #   - cannot be reached via a typed `#<handle>` reply
        #
        # Call `self.internal true` in the subclass body to opt in.
        # Default is false (all handlers are public unless declared otherwise).
        def internal(flag = nil)
          if flag.nil?
            @internal ||= false
          else
            @internal = flag ? true : false
          end
        end

        # Predicate form — returns true for internal handlers.
        def internal?
          @internal ||= false
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
      # @param event          [Event]        the source follow-up-able event.
      # @param rest           [String]       everything after `#<handle> `.
      # @param conversation   [Conversation] the owning conversation.
      # @param period         [String, nil]  analytics window threaded from the reply.
      # @param viewport_width [Integer, String, nil] scrollback width for list auto-fill.
      # @param channel        [String, nil]  channel scope threaded from the reply.
      # @return [Pito::FollowUp::Result::Mutation | Append | Error]
      def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
        raise NotImplementedError, "#{self.class}#call is not implemented"
      end

      private

      # Config-driven availability gate — verbs.yml (the Matrix, via the Registry)
      # is the SOLE source of truth for which reply verbs a card accepts. No handler
      # keeps a literal allowlist: that drift is exactly what shadowed `game` on the
      # video card. `declared?` is true when `action` is a verb THIS reply_target
      # declares; `undeclared_action` builds this target's invalid_action error.
      # A handler gates with `return undeclared_action(action) unless declared?(action)`,
      # then dispatches the declared verb (special-case or delegate to VerbDelegator).
      def declared?(action)
        Pito::FollowUp::Registry.actions_for(self.class.target_id).include?(action.to_s)
      end

      def undeclared_action(action)
        Pito::FollowUp::Result::Error.new(
          message_key:  "pito.follow_up.#{self.class.target_id}.errors.invalid_action",
          message_args: { action: action.to_s }
        )
      end

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
