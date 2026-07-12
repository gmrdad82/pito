# frozen_string_literal: true

require_relative "../grammar/handler_dsl"

module Pito
  module Slash
    # Base class for all slash-command handlers.
    #
    # ## Contract
    #
    # Every concrete subclass MUST:
    # - Set `self.tool = :symbol` — the command word (e.g. `:config`, `:help`).
    # - Set `self.description_key = "pito.slash.<tool>.descriptions.<tool>"` — I18n key.
    # - Implement `#call` → returning `Pito::Slash::Result::Ok` or `Pito::Slash::Result::Error`.
    #
    # ## Class-level DSL (via `Pito::Grammar::HandlerDsl`)
    #
    # ```ruby
    # grammar do
    #   literal :provider, source: :config_providers
    #   enum    :state,    source: :on_off, optional: true, when: { provider: %w[sound fx] }
    #   auth    :authenticated_only   # or :any
    #   description_key "pito.grammar.slash.<tool>"
    # end
    # ```
    #
    # - `auth :authenticated_only` — callers gate the handler; the dispatcher
    #   checks the grammar spec's `auth` field before calling `#call`.
    # - `auth :any` — accessible without authentication (e.g. `/help`).
    #
    # ## Instance accessors (available in `#call`)
    #
    # - `invocation` (`Pito::Slash::Invocation`) — tool, args, kwargs, raw string.
    # - `conversation` (`Conversation`) — the active conversation record.
    # - `authenticated` (Boolean) — whether the request was authenticated.
    #
    # ## `--help` / `-h` intercept path
    #
    # The dispatcher intercepts `--help` / `-h` in the raw input *before* constructing
    # the handler and delegates to `Pito::Slash::HelpBuilder`.  Handlers that also
    # want to respond to provider-scoped help (e.g. `/config google --help`) should
    # override `#show_help`.  The invariant: **`#call` is never invoked when the raw
    # input contains `--help` or `-h`** — no side effects occur on help requests.
    #
    # ## `inherited` reset semantics
    #
    # `Handler.inherited` clears `@tool`, `@description_key`, and all grammar ivars on
    # every subclass so that class-level DSL assignments in one handler never bleed into
    # another, even when both inherit from the same base.
    class Handler
      extend Pito::Grammar::HandlerDsl

      attr_reader :invocation, :conversation, :authenticated

      def initialize(invocation:, conversation:, authenticated: true)
        @invocation    = invocation
        @conversation  = conversation
        @authenticated = authenticated
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      # Returns true when the raw input contains the --help flag.
      # Handlers call `return show_help if help?` at the top of #call.
      def help?
        invocation.raw.match?(/--help\b/)
      end

      # Default --help response. Override in each handler to provide
      # command-specific usage. The boilerplate is: (1) add
      # `return show_help if help?` at the top of #call, and (2) override
      # this method with actual content.
      def show_help
        Pito::Slash::Result::Ok.new(events: [
          {
            kind:    :system,
            payload: { text: "No --help defined for /#{self.class.tool}. Try /help for the command list." }
          }
        ])
      end

      class << self
        def tool
          @tool or raise NotImplementedError, "#{name} must define self.tool"
        end

        def tool=(value)
          @tool = value
        end

        def description_key
          @description_key or raise NotImplementedError, "#{name} must define self.description_key"
        end

        def description_key=(value)
          @description_key = value
        end

        # When true, the dispatcher skips the generic positional-arity guard and
        # lets the handler validate its own argument count (opt-out mechanism).
        # Set `self.validates_own_arity = true` on handlers whose first positional
        # arg is polymorphic (e.g. Games — subcommand keyword with optional title).
        def validates_own_arity
          @validates_own_arity || false
        end

        def validates_own_arity=(value)
          @validates_own_arity = value
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@tool, nil)
          subclass.instance_variable_set(:@description_key, nil)
          subclass.instance_variable_set(:@validates_own_arity, false)
          subclass.reset_grammar_ivars!
        end
      end
    end
  end
end
