# Pito::AuthDialogComponent — non-dismissible TOTP login overlay.
#
# Purpose:
#   Renders a full-viewport overlay when `Current.session.nil?`. Sits above
#   all panel chrome so the owner can see the structural skeleton without
#   seeing live data. Not dismissible by Esc / backdrop — disappears only on
#   a successful POST /login (full-page reload).
#
#   All interactive and content elements compose via ViewComponents:
#   - Tui::HintComponent      — login error line (severity: :danger)
#   - Tui::TotpCodeComponent  — 6-digit (mode: :digits) or 8-char (mode: :backup)
#   - Tui::ActionComponent    — [log in] submit + [use backup code] toggle
#   - Tui::CodeComponent      — enrollment hint with [ copy ] action
#
# Kwargs: none required.
#
# Variants: none.
#
# Focusables:
#   - digit boxes (6)       — primary TOTP segmented input (autofocused on digit 1)
#   - backup char boxes (8) — revealed via toggle
#   - `[ log in ]`          — submit action
#   - `[ use backup code ]` / `[ use TOTP code ]` — toggle action
#   - `[ copy ]`            — clipboard action (only when totp_not_enrolled?)
#
# Mode behavior:
#   Unconditionally shown when the layout detects `Current.session.nil?`.
#
# Cable subscriptions: none (unauthenticated context; cable never opens).
#
# Related:
#   app/views/layouts/application.html.erb — renders this component
#   app/controllers/sessions_controller.rb — handles POST /login
#   app/components/tui/totp_code_component.rb  — unified segmented input
#   app/components/tui/action_component.rb     — bracketed action primitive
#   app/components/tui/code_component.rb       — copyable command block
#   app/javascript/controllers/pito_auth_dialog_controller.js
#   config/locales/tui/en.yml — tui.auth.* keys
class Pito::AuthDialogComponent < ViewComponent::Base
  # Returns true when TOTP has not been enrolled yet.
  # Used to render the operator hint in the dialog body.
  def totp_not_enrolled?
    !AppSetting.totp_enabled?
  end

  # The flash alert from the previous failed POST /login attempt.
  # Reads from the Rails flash; nil when no prior failure.
  def login_error
    helpers.flash[:alert].presence
  end
end
