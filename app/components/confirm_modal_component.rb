class ConfirmModalComponent < ViewComponent::Base
  # `modal_actions_key:` — optional. When present, renders as
  # `data-modal-actions-key="<key>"` on the `<dialog>`. The
  # `leader-menu` Stimulus controller picks the matching entry from
  # `config/keybindings.yml` `modal_actions:` and shows ONLY those
  # action rows in the popup whenever this dialog is open. The
  # reindex-confirm modal passes `"reindex_confirm"`; a future
  # generic confirm modal can pass its own key without forking the
  # component.
  def initialize(id:, title:, confirm_path:, confirm_method: :delete,
                 body: nil, confirm_label: "-",
                 cancel_label: "cancel", destructive: true,
                 modal_actions_key: nil)
    @id = id
    @title = title
    @body = body
    @confirm_label = confirm_label
    @confirm_path = confirm_path
    @confirm_method = confirm_method
    @cancel_label = cancel_label
    @destructive = destructive
    @modal_actions_key = modal_actions_key
  end

  def confirm_button_classes
    classes = [ "bracketed" ]
    classes << "text-danger" if @destructive
    classes.join(" ")
  end
end
