# frozen_string_literal: true

module Pito
  module FollowUp
    # Registry — maps reply_target strings to their handler class.
    #
    # Handler subclasses are auto-registered via the inherited hook in
    # Pito::FollowUp::Handler.  The registry is populated at load time,
    # so all handlers must be loaded (eager-load in production; spec helpers
    # require them explicitly).
    #
    # In tests, register fake handlers directly:
    #   Pito::FollowUp::Registry.register(MyFakeHandler)
    # or reset the registry between examples:
    #   Pito::FollowUp::Registry.reset!
    #
    # API:
    #   Registry.register(handler_class)     — add a handler class.
    #   Registry.for(target_id)              — handler class (or nil if unknown).
    #   Registry.mode_for(target_id)         — :mutate / :append (or nil).
    #   Registry.all                         — Hash { target_id => handler_class }.
    #   Registry.reset!                      — clear all registrations (test use only).
    module Registry
      @handlers = {}

      class << self
        def register(handler_class)
          id = handler_class.target_id
          raise ArgumentError, "Handler #{handler_class} has no target id" if id.blank?
          @handlers[id] = handler_class
        end

        # Returns the handler CLASS for the given target id, or nil if unknown.
        def for(target_id)
          @handlers[target_id.to_s]
        end

        # Returns the mode (:mutate / :append) for the given target id, or nil.
        def mode_for(target_id)
          @handlers[target_id.to_s]&.handler_mode
        end

        # Returns the declared action words for the given target id (the verbs a
        # user can type after `#<handle> `), or [] if unknown. Used by the
        # suggestions engine to offer target-aware follow-up completions.
        def actions_for(target_id)
          @handlers[target_id.to_s]&.actions || []
        end

        # Force-load every handler under Pito::FollowUp::Handlers so the
        # `inherited` hook registers them. Handlers otherwise register lazily
        # (only when their file is first referenced), which left the registry
        # empty for callers like the suggestions engine that run before any
        # follow-up reply. Idempotent — safe to call on every to_prepare.
        def register_all!
          return unless Pito::FollowUp.const_defined?(:Handlers)

          Pito::FollowUp::Handlers.constants.each do |c|
            Pito::FollowUp::Handlers.const_get(c)
          end
        end

        # Snapshot of all registered handlers.
        def all
          @handlers.dup
        end

        # Clear all registrations.  For test isolation only.
        def reset!
          @handlers = {}
        end
      end
    end
  end
end
