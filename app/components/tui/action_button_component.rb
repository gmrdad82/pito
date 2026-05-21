module Tui
  # Canonical bracketed-button for action-bus dispatched actions (ADR 0018).
  # Click flows through `window.Pito.dispatchAction(action_name)` via the
  # `action-trigger` Stimulus controller.
  #
  # Use this for every user-triggerable button-shaped action: reindex,
  # revoke, clear webhook, etc. Action registered in `Pito::ActionRegistry`.
  #
  # @param action_name [Symbol] ActionRegistry key (e.g. :reindex_meilisearch)
  # @param label [String] visible text inside the brackets
  # @param focusable [Hash, nil] {key:, style:} for j/k cursor list, or nil
  # @param data [Hash] additional data-* attrs (snake_case → kebab-case)
  class ActionButtonComponent < ViewComponent::Base
    def initialize(action_name:, label:, focusable: nil, data: {})
      @action_name = action_name
      @label = label
      @focusable = focusable
      @data = data || {}
    end

    attr_reader :label

    def data_attrs
      attrs = {
        "controller" => "action-trigger",
        "action" => "click->action-trigger#dispatch",
        "action-name" => @action_name.to_s
      }
      if @focusable
        attrs["tui-focusable"] = @focusable[:key].to_s
        attrs["tui-focusable-style"] = @focusable[:style].to_s
      end
      @data.each { |k, v| attrs[k.to_s.tr("_", "-")] = v.to_s }
      attrs
    end
  end
end
