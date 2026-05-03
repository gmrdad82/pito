class ConfirmModalComponent < ViewComponent::Base
  def initialize(id:, title:, confirm_path:, confirm_method: :delete,
                 body: nil, confirm_label: "delete",
                 cancel_label: "cancel", destructive: true)
    @id = id
    @title = title
    @body = body
    @confirm_label = confirm_label
    @confirm_path = confirm_path
    @confirm_method = confirm_method
    @cancel_label = cancel_label
    @destructive = destructive
  end

  def confirm_button_classes
    classes = [ "bracketed" ]
    classes << "text-danger" if @destructive
    classes.join(" ")
  end
end
