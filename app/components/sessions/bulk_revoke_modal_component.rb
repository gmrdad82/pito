# 2026-05-18 — Beta-3 lane B candidate B8.
#
# Extracted from `app/views/settings/_security_pane.html.erb`
# (the `<dialog id="revoke_sessions_modal">` block) — the in-page
# confirm modal the bulk-revoke flow opens via the
# `sessions-bulk-revoke` Stimulus controller.
#
# This is a pure render shim. The modal's title, conditional warning,
# and form `action` are all rewritten at click time by the
# `sessions-bulk-revoke` controller based on the current checkbox
# selection — so there are no per-instance inputs. The render carries:
#
#   * The `<dialog id="revoke_sessions_modal">` mount with the
#     `confirm-modal` controller wired for Esc / outside-click close.
#   * Stimulus targets the `sessions-bulk-revoke` controller writes
#     into: `modal`, `modalTitle`, `modalWarning`, `modalForm`.
#   * A `form_with` whose `action` carries the literal `0` ids segment
#     — the route constraint `[0-9,]+` requires a digit, and `0` is
#     filtered out by `parse_ids` server-side as a safety net. The
#     controller rewrites the segment to
#     `/settings/sessions/revokes/<real-ids>` when the modal opens.
#   * A `submit->sessions-bulk-revoke#refreshCsrf` hook that copies the
#     current `<meta name="csrf-token">` value into the form's hidden
#     token field immediately before submit, in case the baked token
#     has gone stale (TOTP gate completion, sign-in elsewhere, etc.).
#   * `[revoke]` / `[cancel]` action buttons.
#
# Does NOT replace `ConfirmModalComponent` — the bulk-revoke dialog
# has a unique requirement (dynamic title + dynamic warning + dynamic
# form action from Stimulus) that the generic component does not
# support. Keep both. The conditional `<% if @sessions.any? %>` stays
# at the caller site in `_security_pane.html.erb` — the component
# itself is unconditional.
module Sessions
  class BulkRevokeModalComponent < ViewComponent::Base
    def initialize
    end
  end
end
