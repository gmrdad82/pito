# Reusable 6-box segmented input for a TOTP code.
#
# Used by both the 2FA enrollment page (`settings/security/totps/new`)
# and the post-password login challenge page
# (`login/totp_challenges/show`). The visual pattern is the same
# Slack-style segmented input that lives on the layout-level TOTP
# re-verification dialog (`shared/_totp_verification_modal`) — six
# 28px boxes, monospace bold, link-color focus ring — extracted here
# so the enrollment + login surfaces stop rendering a single bare
# `<input type="text">` and pick up the proper one-digit-per-cell
# affordance.
#
# Markup contract:
#
#   - 6 visible `<input>` boxes with `inputmode="numeric"`,
#     `pattern="\d{1}"`, `maxlength="1"`, and
#     `data-totp-code-input-target="digit"`.
#   - The FIRST visible box carries `autocomplete="one-time-code"` so
#     iOS / Android keyboards offer SMS-style autofill into the
#     leftmost cell; the rest carry `autocomplete="off"` so the
#     password manager does not try to fill them independently.
#   - A hidden `<input name="<field>">` sibling holds the
#     concatenated 6-digit value. The Stimulus controller writes the
#     concatenation into the hidden field on every keystroke / paste
#     so a form submit (Enter inside any box, or a click on the page's
#     own submit button) carries `params[<field>] = "123456"` exactly
#     like the legacy single-bare-input did. Neither backend
#     controller needs to change.
#   - The container element carries `data-controller="totp-code-input"`
#     so a fresh DOM (Turbo render, modal swap) re-mounts the
#     controller and rebinds the boxes.
#
# The visible boxes are intentionally NOT named — only the hidden
# field carries the `code` param. Naming the 6 visible boxes
# `code` too would produce 6 separate values in the submitted form
# data, overriding the concatenated hidden value.
#
# Layout choice — the component does NOT wrap the form. The caller
# wraps the component in its own `form_with` so the form's URL,
# method, and submit button live in the consumer template. The
# component is JUST the input cluster.
class TotpCodeInputComponent < ViewComponent::Base
  # @param field [Symbol, String] form-param name carried on the hidden
  #   field that holds the concatenated 6-digit value. Backend
  #   controllers read this as `params[field]`. Defaults to `:code`
  #   since both current consumers (`Login::TotpChallengesController`
  #   and `Settings::Security::TotpsController`) read `params[:code]`.
  # @param autofocus [Boolean] when true, the first box renders with
  #   `autofocus` so the page lands with the caret already in the
  #   leftmost cell. Defaults to true — both consumer pages are
  #   focused dialogs where the user came to type the code.
  def initialize(field: :code, autofocus: true)
    @field = field.to_s
    @autofocus = autofocus
  end

  attr_reader :field

  def autofocus?
    @autofocus
  end
end
