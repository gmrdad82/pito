module Pito
  # `Pito::ActionDispatcher` — Ruby-side action-bus dispatcher.
  #
  # Symmetric to `window.Pito.dispatchAction(name)` (defined in
  # `app/javascript/pito_actions.js`). Used by MCP tool surfaces and
  # the Rust TUI client (via in-process Ruby when embedded, or via
  # HTTP that calls Rails endpoints that delegate here).
  #
  # ## Contract
  #
  # `Pito::ActionDispatcher.dispatch(name, params = {}, confirm: false)`
  #
  # - `name` (Symbol) — registered action key (e.g., `:reindex_meilisearch`)
  # - `params` (Hash) — action-specific parameters
  # - `confirm` (Boolean) — for destructive actions; first call returns
  #   a confirmation payload, second call with `confirm: true` executes
  #
  # ## Behavior
  #
  # 1. Resolve via `Pito::ActionRegistry[name]` → returns a `Pito::Action`
  #    value object (path_proc, method, confirmation hash, i18n_key,
  #    cable_panel)
  # 2. If action has `:confirmation` AND `confirm: false`:
  #    return a `Result` with `status: :confirmation_required` and a
  #    payload describing the action + message
  # 3. If action has `:confirmation` AND `confirm: true`, OR no confirmation:
  #    execute via in-process HTTP-like call (or direct service invocation,
  #    depending on caller context — MCP HTTP-based, CLI in-process)
  # 4. Return a `Result` with `status: :enqueued | :completed` and an
  #    action-specific payload, or `status: :error` with an `error` hash
  #    on failure
  #
  # ## Use cases
  #
  # - MCP: `mcp_tool_call → Pito::ActionDispatcher.dispatch(name, params, confirm: ...)`
  # - CLI: `pito reindex meilisearch → in-process or HTTP-call → Pito::ActionDispatcher.dispatch`
  # - Rails internal: any code that wants to trigger the action without a
  #   web request can call `Pito::ActionDispatcher.dispatch` directly
  #
  # ## Implementation notes (initial — to be expanded as MCP/CLI mature)
  #
  # This class is a SKELETON for the action-bus Ruby-side dispatch.
  # Initial implementation:
  # - Looks up action via `Pito::ActionRegistry[name]`
  # - Handles confirmation gate
  # - For execution: raises `NotImplementedError` if the action requires
  #   a real HTTP/web context to execute (CSRF, session, etc.); MCP/CLI
  #   layers may pass an authenticated `Current.user` context
  # - Returns structured `Result` objects (no exceptions for known errors)
  #
  # As MCP/CLI integrations land, this class grows execution paths
  # (in-process service calls, HTTP-back-to-self for full Rails context, etc.)
  class ActionDispatcher
    Result = Struct.new(:status, :payload, :error, keyword_init: true) do
      def confirmation_required? = status == :confirmation_required
      def success? = !error
    end

    class << self
      def dispatch(name, params = {}, confirm: false, current_user: nil)
        action = Pito::ActionRegistry[name.to_sym]

        if action.confirmation && !confirm
          return Result.new(
            status: :confirmation_required,
            payload: {
              action: name.to_sym,
              message: I18n.t("#{action.i18n_key}.confirm_message",
                              default: action.confirmation[:title] || "confirm action"),
              danger: action.confirmation[:danger] || false
            },
          )
        end

        # Execution: this is a SKELETON.
        # MCP/CLI integrations will implement in-process or HTTP execution
        # paths as those surfaces mature. For now, raise NotImplementedError
        # so callers know this entry point exists but execution wires aren't
        # wired through.
        raise NotImplementedError,
              "Pito::ActionDispatcher#dispatch execution path " \
              "pending MCP/CLI wire-through (action: #{name})"
      rescue KeyError => e
        Result.new(status: :error, error: { code: :unknown_action, message: e.message })
      end
    end
  end
end
