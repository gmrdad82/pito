class ConfirmModalComponent < ViewComponent::Base
  # `modal_actions_key:` — optional. When present, renders as
  # `data-modal-actions-key="<key>"` on the `<dialog>`. The
  # `leader-menu` Stimulus controller picks the matching entry from
  # `config/keybindings.yml` `modal_actions:` and shows ONLY those
  # action rows in the popup whenever this dialog is open. The
  # reindex-confirm modal passes `"reindex_confirm"`; a future
  # generic confirm modal can pass its own key without forking the
  # component.
  # `turbo:` — optional. Defaults to `false` so every existing caller
  # keeps its current full-page submission semantics (per-game delete,
  # sync confirm, revoke, reindex, ...). Callers that want the form
  # to submit as a Turbo Stream (so the controller's
  # `format.turbo_stream` branch fires and the page does NOT navigate
  # away) pass `turbo: true`. This flips the `<form>`'s
  # `data-turbo` attribute on; the Accept header negotiation handles
  # the rest.
  def initialize(id:, title:, confirm_path:, confirm_method: :delete,
                 body: nil, confirm_label: nil,
                 cancel_label: nil, destructive: true,
                 modal_actions_key: nil, turbo: false)
    @id = id
    @title = title
    @body = body
    @confirm_label = confirm_label || I18n.t("common.actions.delete_short")
    @confirm_path = confirm_path
    @confirm_method = confirm_method
    @cancel_label = cancel_label || I18n.t("common.actions.cancel")
    @destructive = destructive
    @modal_actions_key = modal_actions_key
    @turbo = turbo
  end

  def confirm_button_classes
    classes = [ "bracketed" ]
    classes << "text-danger" if @destructive
    classes.join(" ")
  end
end
