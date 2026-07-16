module Pito
  # `Pito::ActionDispatcher` — Ruby-side action-bus dispatcher.
  #
  # Symmetric to `window.Pito.dispatchAction(name)` (defined in
  # `app/javascript/pito_actions.js`).
  #
  # ## Contract
  #
  # `Pito::ActionDispatcher.dispatch(name, params = {}, confirm: false)`
  #
  # - `name` (Symbol) — registered action key (e.g., `:calendar_next_month`)
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
  #    execute via direct service invocation
  # 4. Return a `Result` with `status: :enqueued | :completed` and an
  #    action-specific payload, or `status: :error` with an `error` hash
  #    on failure
  #
  # ## Use cases
  #
  # - Rails internal: any code that wants to trigger the action without a
  #   web request can call `Pito::ActionDispatcher.dispatch` directly
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

        raise NotImplementedError,
              "Pito::ActionDispatcher#dispatch execution path " \
              "not yet wired (action: #{name})"
      rescue KeyError => e
        Result.new(status: :error, error: { code: :unknown_action, message: e.message })
      end
    end
  end
end
