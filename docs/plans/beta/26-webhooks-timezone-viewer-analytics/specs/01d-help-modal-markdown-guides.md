# 01d — Help-modal Markdown guides (Slack + Discord)

> Beginner-friendly Markdown guides for both providers, rendered server-side via
> Phase 16's existing Markdown renderer, opened from the `[help]` link in each
> Settings pane. No JS `confirm` / `alert` / `prompt`. Can ship parallel with
> 01b + 01c. Implementation agent: `pito-rails`.

## Goal

Write two beginner-friendly Markdown guides — one for Slack, one for Discord —
covering the full path from "I have never made a webhook before" to "the URL is
pasted in pito and the test message landed in my channel." Render through Phase
16's existing Markdown renderer (verify exact class on dispatch — likely
`MarkdownRenderer` or `NotificationFormatter::Markdown`). Open in a modal dialog
from the `[help]` link in the Slack + Discord panes. The modal pattern mirrors
the Phase 7.5 keyboard-shortcuts modal: Esc closes, backdrop click closes, focus
trap, no JS `confirm`.

## Files touched

### New

- `app/views/settings/webhooks/help/slack.md` — beginner guide for Slack.
  Sections:
  1. Open `https://api.slack.com/apps` in a browser.
  2. Click `Create New App` → `From scratch`.
  3. Name the app (`pito` or similar) + pick the Slack workspace.
  4. In the left sidebar, click `Incoming Webhooks` → toggle it on.
  5. Scroll down, click `Add New Webhook to Workspace` → pick the channel where
     pito should post.
  6. Copy the resulting `https://hooks.slack.com/services/T.../B.../...` URL.
  7. Paste it into pito's Slack pane on `/settings`. Hit `[update]`.
  8. Watch the channel — a "hi from pito" test message should land within a
     second. If not, see "Troubleshooting."
  - **Troubleshooting** section: invalid-URL error meaning, ping-failed error
    meaning, what to do if the channel was deleted.
- `app/views/settings/webhooks/help/discord.md` — beginner guide for Discord.
  Sections:
  1. Open the target Discord server. Make sure you have `Manage Webhooks`
     permission on the channel.
  2. Right-click the channel → `Edit Channel` → `Integrations` → `Webhooks` →
     `New Webhook`.
  3. Optionally rename the webhook (e.g., `pito`) + set an avatar.
  4. Click `Copy Webhook URL`. The URL is
     `https://discord.com/api/webhooks/<snowflake>/<token>`.
  5. Paste it into pito's Discord pane on `/settings`. Hit `[update]`.
  6. Watch the channel — a "hi from pito" test message should land within a
     second. If not, see "Troubleshooting."
  - **Troubleshooting** section: invalid-URL error meaning, ping-failed error
    meaning, permission errors, what to do if the channel / integration was
    deleted.
- `app/controllers/settings/webhooks/help_controller.rb` — single `show` action.
  Route: `GET /settings/webhooks/help/:provider`. `:provider` is `slack` or
  `discord` (enum-validated). Reads the matching `.md` file, renders through the
  existing Markdown renderer, returns an HTML fragment suitable for the modal's
  `<turbo-frame>` target. No layout (modal-only render).
- `app/components/webhook_help_modal_component.rb` — ViewComponent wrapping the
  modal chrome. Slot: `default` (the rendered HTML fragment). Renders with
  `<dialog>` element + Stimulus `modal_controller` reused from the
  keyboard-shortcuts modal. Esc + backdrop click + `[close]` bracketed link all
  close.
- `app/components/webhook_help_modal_component.html.erb` — markup.
- Specs:
  - `spec/components/webhook_help_modal_component_spec.rb` — rendering happy +
    sad (missing slot, invalid provider). ViewComponent convention.
  - `spec/controllers/settings/webhooks/help_controller_spec.rb` (or request
    spec) — `GET /settings/webhooks/help/slack` returns 200 with rendered
    Markdown. `GET .../discord` ditto. Invalid provider (`?provider=mars`)
    returns 404. Unauthenticated returns 401 / redirect to login.
  - `spec/system/settings_webhook_help_spec.rb` — critical journey: open
    `/settings`, click `[help]` in the Slack pane, modal opens with the rendered
    guide, Esc closes, click backdrop closes.

### Edited

- `config/routes.rb` —
  `namespace :settings do; namespace :webhooks do; get "help/:provider", to: "help#show", constraints: { provider: /slack|discord/ }, as: :help ; end ; end`.
  Friendly URL preserved: `/settings/webhooks/help/slack`,
  `/settings/webhooks/help/discord`.
- `app/views/settings/_slack_pane.html.erb` (from 01b) — `[help]` link wired to
  the modal turbo frame. Stimulus action: open modal, fetch the fragment from
  `/settings/webhooks/help/slack`.
- `app/views/settings/_discord_pane.html.erb` (from 01c) — same wiring, Discord
  variant.

### Read-only inputs

- The Phase 16 Markdown renderer (verify class name on dispatch).
- The Phase 7.5 keyboard-shortcuts modal Stimulus controller + ViewComponent
  pattern — reused as the modal scaffolding template.

## Acceptance

- [ ] Two `.md` files exist under `app/views/settings/webhooks/help/`. Content
      covers every step a true beginner needs, with no assumed knowledge.
- [ ] `GET /settings/webhooks/help/slack` returns the rendered HTML fragment
      with the Slack guide. `GET .../discord` returns the Discord guide. Invalid
      provider returns 404.
- [ ] The `[help]` link in each Settings pane opens the modal via Turbo Frame;
      the fragment is fetched server-side; Markdown rendering happens
      server-side (no JS Markdown library).
- [ ] Modal closes on Esc, backdrop click, and `[close]` link.
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm`. The
      `<dialog>` element + Stimulus modal_controller is the only modal surface.
- [ ] Friendly URL preserved.
- [ ] Spec pyramid covers: ViewComponent, request (controller), system (critical
      journey for the open-and-close flow).
- [ ] Both guides render correctly: code blocks, links, headings, lists.
      Markdown renderer's existing styling applies (no custom CSS in this
      sub-spec).
- [ ] Brakeman + bundler-audit clean.

## Manual test recipe

1. `bin/dev` running. Open `/settings`. Locate the Slack pane.
2. Click `[help]`. A modal opens with the Slack guide rendered. Confirm
   headings, lists, code blocks, links all render as expected.
3. Press Esc — modal closes.
4. Click `[help]` again. Click outside the modal (on the backdrop) — modal
   closes.
5. Click `[help]` again. Click the `[close]` bracketed link inside the modal —
   closes.
6. Repeat for the Discord pane.
7. Walk a hypothetical beginner through both guides side-by-side: every step
   should be doable without reaching for external docs or assuming any prior
   knowledge of Slack / Discord webhooks.

## Cross-stack scope

| Surface | Status | Note                                               |
| ------- | ------ | -------------------------------------------------- |
| Web     | in     | Primary surface.                                   |
| MCP     | out    | Help docs are HTML-modal-only.                     |
| CLI     | out    | No help-modal in the TUI.                          |
| Website | out    | (Future: mirror these guides on the marketing site |
|         |        | once the docs surface ships in Phase 14 — out of   |
|         |        | scope here.)                                       |

## Open questions

1. **Markdown renderer identity.** Phase 16 ships a renderer; the exact class
   name needs to be verified during dispatch. **Confirm with user or read Phase
   16's spec on dispatch.**
2. **Screenshots vs ASCII-art steps.** The guides describe Slack / Discord UI
   buttons by name. Inline screenshots make the guides more beginner-friendly
   but bloat the repo. v1 leans on text-only descriptions (no screenshots).
   **Confirm with user.**
3. **Guide refresh cadence.** Slack / Discord rename their UI buttons
   occasionally. v1 commits the guides as-is; future drift handled in a
   docs-keeper follow-up. **Confirm with user.**
4. **Localization.** Guides are English-only for v1. **Confirm with user — pito
   is single-locale today, but worth confirming.**
