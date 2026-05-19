# Layout-level "about" modal (2026-05-19).
#
# Mounted by the application layout at id `about-modal` so the global
# leader-menu + flat keybindings can target it. Sizing mirrors the
# smallest existing modal (`ConfirmModalComponent` →
# `dialog.confirm-modal { max-width: 420px; padding: 0 }` with
# `.confirm-modal-inner { padding: 12px 16px }` and the shared
# `.modal-footer` hairline-above-actions pattern).
#
# Content blocks (locked in chat 2026-05-19):
#   - project name + subtitle (muted)
#   - version + revision K-V grid (`<dl>` with `grid-template-columns:
#     auto 1fr` for column-aligned values, no colons)
#   - revision value is a bracketed link to the GitHub commit, new tab
#     (reuses `ApplicationHelper#git_sha`; falls back to a muted
#     em-dash when no SHA is available, e.g. detached deploy)
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

  # GitHub commit URL pattern (same string ApplicationHelper#version_label uses).
  GITHUB_COMMIT_BASE = "https://github.com/gmrdad82/pito/commit/".freeze

  def version_string
    "v#{app_version}"
  end

  def sha
    git_sha
  end

  def commit_url
    return nil unless sha

    "#{GITHUB_COMMIT_BASE}#{sha}"
  end

  def env
    Rails.env
  end

  # Mirrors the footer copy in `layouts/application.html.erb` so the two
  # surfaces stay in lockstep. `Date.current.year` matches the footer's
  # dynamic year.
  def copyright_text
    "© #{Date.current.year} — all rights reserved."
  end
end
