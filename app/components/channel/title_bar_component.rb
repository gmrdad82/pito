# Phase 37 Wave A1 — `/channels` title bar.
#
# Renders the dashboard title row:
#
#   channels [+][-]
#
# Layout (locked 2026-05-19 user-confirmed; see
# `docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md`
# §"Wave A1 layout (locked 2026-05-19, user)"):
#
#   * "channels" plain text label on the left
#   * single space
#   * `[+]` bracketed link — future entry point for the multi-channel
#     OAuth picker modal (Wave A16 / B13). Wave A1 ships placeholder
#     `href="#"`.
#   * `[-]` bracketed link, DESTRUCTIVE (red) — future entry point for
#     the bulk-revoke / delete flow. Wave A1 ships placeholder
#     `href="#"`. Destructive coloring comes from
#     `BracketedLinkComponent(destructive: true)` which applies the
#     `.text-danger` class wired to `--color-danger` (see
#     `app/assets/tailwind/application.css` L54 light / L193 dark and
#     `docs/design.md` L106).
class Channel::TitleBarComponent < ViewComponent::Base
end
