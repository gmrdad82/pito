# Layout-level "about" modal (2026-05-19, SHA row removed 2026-05-20).
#
# Mounted by the application layout at id `about-modal` so the global
# leader-menu + flat keybindings can target it. Sizing mirrors the
# smallest existing modal (`ConfirmModalComponent` →
# `dialog.confirm-modal { max-width: 420px; padding: 0 }` with
# `.confirm-modal-inner { padding: 12px 16px }` and the shared
# `.modal-footer` hairline-above-actions pattern).
#
# Content blocks:
#   - project name + subtitle (muted)
#   - version + env K-V grid (`<dl>` with `grid-template-columns:
#     auto 1fr` for column-aligned values, no colons). The VERSION file
#     is the canonical version source; no commit-SHA / revision row is
#     rendered.
#   - copyright line (mirrors the footer string verbatim:
#     `© <year> — all rights reserved.`)
#
# Footer action row: bracketed `[ close ]` LEFT-aligned per the
# design.md "Modal footer alignment" rule, wired to the shared
# `confirm-modal` Stimulus controller (already handles click-outside
# + Escape) so we do not introduce a new controller.
class AboutModalComponent < ViewComponent::Base
  include ApplicationHelper

  # Dialog id is hard-locked — the keybindings YAML targets this id.
  MODAL_ID = "about-modal".freeze

  def version_string
    "v#{app_version}"
  end

  def env
    Rails.env
  end

  # Mirrors the footer copy in `layouts/application.html.erb` so the two
  # surfaces stay in lockstep. `Date.current.year` matches the footer's
  # dynamic year.
  #
  # FB-71 (2026-05-20) — copy now resolves via I18n
  # (`about.modal.copyright`) with a `%{year}` interpolation, so the
  # string flows through the same locale surface as the rest of the
  # about dialog. The pattern itself (`© <year> — all rights reserved.`)
  # is preserved verbatim.
  def copyright_text
    I18n.t("about.modal.copyright", year: Date.current.year)
  end
end
