# ADR 0009 — 2FA verification via shared `<dialog>` modal with segmented 6-digit input

## Status

Accepted, 2026-05-12. [skipci]

## Context

Phase 25 (Login Security + New-Location Approval) shipped TOTP-based 2FA for the
login flow and for sensitive write surfaces. The first iteration wired a plain
`<input type="text" name="totp_code">` field into each form that needed
verification:

- `/login/totp` — the post-password challenge step.
- `/settings/security/totps/...` — enroll / disable / regenerate backup codes.
- `/settings/user` — sensitive user-account writes (email change, password
  rotation).
- `/settings/youtube` (Phase 27 settings revamp) — YouTube credential rotation,
  per ADR 0007.
- `/settings/voyage` — Voyage API key rotation.
- `/settings/slack` — Slack webhook URL rotation.
- `/settings/discord` — Discord webhook URL rotation.

The inline-input shape worked but had three rough edges that surfaced during the
beta2 polish wave (2026-05-11 → 2026-05-12):

- **Inconsistent placement.** Each form embedded the TOTP field next to its own
  fields, which meant seven different layouts and seven different "where is the
  code field" muscle-memory hits for the operator.
- **No paste-fill ergonomics.** The single `type="text"` input accepted a
  6-digit string fine, but the visual surface didn't communicate "6 digits,
  paste from your authenticator" — operators paste a code and then have to find
  the `[submit]` button.
- **Submit cadence.** Operators tab to the field, type six digits, then tab to
  submit. Six digits is a fixed-length input where the natural cadence is "the
  sixth digit IS the submit signal."

The user-directed polish bundle (2026-05-11 `settings + 2FA fix-forward bundle`)
plus the follow-up `2FA modal: auto-submit on 6th digit` work (`29a8a13`)
consolidated the seven inline-field surfaces into a single shared modal flow.

## Decision

Adopt a single shared `<dialog>` modal for every 2FA verification across the
app.

Concretely:

- **Component:** a single `Totp::ModalComponent` (or equivalent) renders a
  `<dialog>` element with a six-cell segmented input. Each cell is a
  single-character `<input maxlength="1">` field wired through a Stimulus
  controller (`totp_modal_controller.js`).
- **Segmented input behavior:**
  - Typing a digit advances focus to the next cell.
  - Backspace clears the current cell and retreats focus.
  - Paste of a 6-character string fills all six cells in one operation.
  - Paste of a longer string takes the first six digit characters and discards
    the rest (handles "123 456" / "123-456" / "123456789" paste sources
    gracefully).
- **Auto-submit on 6th digit.** When the sixth cell receives input AND every
  cell has a digit, the controller submits the surrounding form automatically.
  The `[confirm]` button was dropped — its only role was redundant with the
  auto-submit signal.
- **Generic-flash failure mirroring.** A wrong code surfaces the same generic
  `credentials don't match.` flash the inline-input path used. The modal
  re-opens with cells cleared so the operator can retry.
- **Read-only views are NOT gated.** The modal only fires on submit. Reading
  `/settings/security` or `/settings/user` doesn't require a code.
- **Form integration.** Each gated form embeds a hidden `totp_code` field bound
  to the modal's joined 6-character value. On submit, the modal serializes the
  code into the field, then the form posts as normal.
- **Server-side concern.** `Controllers::Concerns::RecentTotpVerification`
  (introduced in the same bundle) reads `params[:totp_code]` and rejects writes
  when the user has 2FA on. The concern is unchanged by the modal refactor — it
  sees the same `totp_code` param whether the value came from an inline field or
  the segmented modal.

The seven inline-field call sites were all rewritten to invoke the modal
component. The inline `<input type="text" name="totp_code">` field shape is
retired; new code paths that need 2FA verification reach for the modal
component.

## Consequences

- **One UX across every 2FA surface.** Login, settings, webhook rotations,
  user-account writes, credential rotations all surface the same modal. Operator
  muscle memory transfers across surfaces.
- **Auto-submit removes a click.** The sixth-digit auto-submit cadence drops the
  `[confirm]` press; the operator's last action is typing the sixth digit,
  period.
- **Paste-fill works correctly across authenticator apps.** Google Authenticator
  and 1Password both copy a `123 456` shape; the modal's paste-cleanup logic
  strips the space.
- **CSS surface is centralized.** The segmented-cell layout (six cells,
  monospaced, equal-width, focus-ring on the active cell) lives in one place.
  Theming flows through CSS variables — no per-form override.
- **Spec surface expanded.** A Stimulus-controller spec covers the focus +
  paste + auto-submit behavior; per-form request specs assert the modal is
  rendered (vs. the inline-input shape).
- **Backward compatibility.** Browsers without `<dialog>` support (effectively
  none in pito's target audience as of 2026) would degrade — the controller
  falls back to a plain submit button if the dialog API is unavailable. Not
  exercised but kept defensively.

## Open questions (deferred)

- **Recovery code modal.** The backup-code flow currently surfaces a longer
  input shape (8 characters, restricted alphabet per ADR 0007 sibling). Whether
  to fold backup-code entry into the same modal (with a "use backup code" link
  inside the modal) or keep it on a separate page is open. Today it lives on a
  separate page; defer the merge until a user surfaces the friction.
- **WebAuthn / hardware key fallback.** The modal's segmented input presupposes
  a 6-digit TOTP. If WebAuthn ships later as a second factor option, the modal
  will need a "use security key instead" affordance. Deferred — WebAuthn is not
  on the beta roadmap.

## Alternatives considered

- **Keep the inline `<input type="text" name="totp_code">` field on each form.**
  Rejected. Seven different layouts, no paste-fill polish, no auto-submit. Each
  rough edge is small; the cumulative friction was enough to warrant the
  refactor.
- **Single inline segmented input (no modal wrapper) on each form.** Rejected.
  The modal wrapper centralizes the focus management and the paste-fill
  behavior; without it, each form would still own the segmented-cell layout.
- **Replace TOTP entirely with WebAuthn / passkeys.** Deferred. The modal is a
  much smaller change and lands today; passkey adoption can layer on top later
  as a sibling factor.

## Date

2026-05-12. [skipci]

## Related

- `app/components/totp/modal_component.rb` — the shared modal component.
- `app/javascript/controllers/totp_modal_controller.js` — Stimulus controller
  wiring focus, paste, auto-submit.
- `app/controllers/concerns/recent_totp_verification.rb` — the server-side gate
  the modal feeds.
- `docs/plans/beta/25-login-security-and-new-location-approval/log.md` — origin
  of the `RecentTotpVerification` concern and the inline-field shape the modal
  replaces.
- ADR 0007 — YouTube credentials on `AppSetting`; one of the call sites the
  modal now serves.
- `docs/auth.md` — operator-facing 2FA documentation; update once the modal
  stabilizes through one more polish pass.
