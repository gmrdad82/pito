# Phase 7.5 — Step 01 — Rails-side Hygiene Sweep

> First of two hygiene sweeps for Phase 7.5. Bundles four small, independent
> Rails-side cleanups into one rails-impl dispatch and one commit. None of these
> change product behavior; all of them remove drift between the codebase and the
> conventions / decisions that Phase 6 + Phase 7 + Path A2 settled.

---

## Goal

Land four Rails-side cleanups in a single dispatch:

1. **`:unprocessable_entity` → `:unprocessable_content`** migration across every
   controller still using the deprecated value.
2. **OmniAuth scope-walk fallback simplification** in
   `config/initializers/omniauth.rb` (Phase 6+7+A2 reviewer Should-Fix #4).
3. **Channel Revamp orphans cleanup** — delete the orphaned `_confirm_dialog`
   partial, its Stimulus controller, and the unused `confirm:` kwarg on
   `BracketedLinkComponent`.
4. **`Settings::SessionsController .unscoped` audit** — document the intentional
   usage with an inline comment (per Q1 below; if the user flips Q1 to "fix the
   underlying bug", this item splits out of the sweep).

Net result: one commit, "Phase 7.5 hygiene: unprocessable_content, omniauth
scope-walk, channel-revamp orphans, sessions unscoped audit" (or similar
one-line summary the master agent picks).

## Files touched

### Item 1 — `:unprocessable_entity` migration

Reviewer-flagged hits:

- `app/controllers/settings/oauth_applications_controller.rb` (lines 44, 61) —
  flagged Phase 6+7+A2 review Should-Fix #2.
- `app/controllers/settings/tokens_controller.rb` — flagged in the prior Phase
  5+5.5 review.

Broad-sweep audit (Q2 default = broad sweep): `rg ':unprocessable_entity' app/`
to surface every remaining hit. Update each.

Tests:

- Any request spec asserting the deprecated symbol gets updated to
  `:unprocessable_content`.

### Item 2 — OmniAuth scope-walk simplification

- `config/initializers/omniauth.rb` — collapse the belt-and-suspenders nil-walk
  fallbacks to a single direct lookup with an early-fail (raise during boot if
  `Rails.application.credentials.google_oauth.client_id` / `client_secret` is
  missing).

Tests:

- Existing OmniAuth-related specs stay green
  (`spec/requests/auth/google_callbacks_spec.rb`,
  `spec/system/google_oauth_flow_spec.rb`).
- Optional new spec: `bin/rails runner` smoke that booting with a
  partially-populated `:google_oauth` block raises a clear message — this can
  also be a manual-step in the recipe instead of an implementation-spec ask.

### Item 3 — Channel Revamp orphans cleanup

- DELETE `app/views/shared/_confirm_dialog.html.erb`.
- DELETE `app/javascript/controllers/confirm_dialog_controller.js`.
- EDIT `app/components/bracketed_link_component.rb` — remove the
  accepted-but-ignored `confirm:` kwarg.
- UPDATE `spec/components/bracketed_link_component_spec.rb` to drop any
  `confirm:` examples.

Pre-deletion verification (the implementation agent runs this BEFORE deleting):

```bash
grep -rn "_confirm_dialog\|confirm_dialog_controller\|data-controller=\"confirm-dialog\"" app/
```

Should return zero matches. If it does NOT, STOP and report — there is a caller
that needs to be updated first, and the sweep is no longer safe.

Also grep for `confirm:` kwarg call sites:

```bash
grep -rn "BracketedLinkComponent.*confirm:" app/ spec/
```

Should also return zero matches outside the component definition itself and its
spec.

### Item 4 — `Settings::SessionsController .unscoped` audit

Q1 default (reviewer's lean = (a) the `.unscoped` is intentional and defensive):

- EDIT `app/controllers/settings/sessions_controller.rb` — add a one-paragraph
  comment above the `.unscoped.where(user_id:)` call explaining:
  `BelongsToTenant`'s default scope filters by `Current.tenant_id`; sessions are
  tenant-scoped via the user's membership, but a future multi-tenant user will
  have sessions across tenants; `.unscoped.where(user_id: Current.user.id)` is
  the surface that lets `/settings/sessions` show all of THIS user's sessions
  regardless of which tenant context they were created under. The explicit
  `where(user_id:)` is the load-bearing isolation; the `.unscoped` only opts out
  of the tenant default-scope.

If Q1 flips to (b) — "fix the underlying bug" — this item drops out of the sweep
and lands as a separate spec. The hygiene sweep should NOT silently expand into
a `BelongsToTenant` refactor.

Tests:

- `spec/requests/settings/sessions_spec.rb` continues passing.
- Optional: a comment-only change does not require new specs.

## Acceptance

- [ ] `rg ':unprocessable_entity' app/` returns zero matches (Q2 broad sweep) OR
      returns only the reviewer-listed hits (Q2 narrow sweep) post-fix.
- [ ] `rg ':unprocessable_content' app/` shows the migrated callsites.
- [ ] All updated request specs assert `:unprocessable_content`.
- [ ] `config/initializers/omniauth.rb` no longer contains the chained nil-walk
      fallbacks; loading Rails with a missing credentials key raises during boot
      with a clear message.
- [ ] `app/views/shared/_confirm_dialog.html.erb` gone; the directory contains
      only intentional partials.
- [ ] `app/javascript/controllers/confirm_dialog_controller.js` gone;
      `app/javascript/controllers/index.js` does not register it.
- [ ] `BracketedLinkComponent#initialize` no longer accepts `confirm:`;
      `bracketed_link_component_spec.rb` no longer asserts the kwarg.
- [ ] `Settings::SessionsController#index` carries the audit comment (Q1 = (a))
      OR has been refactored alongside `BelongsToTenant` (Q1 = (b); separate
      spec).
- [ ] `bundle exec rspec` green at expected count (pre-sweep baseline ± any spec
      assertion adjustments). RuboCop clean. Brakeman: warning count unchanged
      or lower.
- [ ] `bin/dev` boots and the login + Google OAuth + sessions UI render without
      regression.

## Manual test recipe

1. `bin/dev` — Web Puma boots cleanly. No "could not load credential key"
   warning.
2. Sign in (`/login`), revoke the session via `/settings/sessions`, confirm the
   `:unprocessable_content` migrations did not change any user-visible behavior
   on the destructive path.
3. Visit `/settings/youtube`. Connect a Google account if not already connected.
   Confirm OmniAuth still routes correctly (regression gate on item 2).
4. Disconnect the Google account, reconnect it. Both paths should behave
   identically to pre-sweep (regression gate).
5. `bin/rails console` → `Rails.application.credentials.google_oauth.client_id`
   returns a non-nil string. Temporarily rename the key (in a scratch
   credentials file), boot the app, confirm Rails fails fast with a clear
   message. Restore.
6. `grep -rn "_confirm_dialog\|confirm_dialog_controller" app/` returns zero
   matches.
7. `grep -rn "BracketedLinkComponent.*confirm:" app/ spec/` returns zero
   matches.
8. `bundle exec rspec` green.

## Cross-stack scope

- Rails — **in scope**.
- `pito` CLI — **out of scope.** No CLI files touched.
- MCP — **out of scope.** No MCP tool changes.
- Cloudflare Pages website — **out of scope.**

## Open questions

- **Q1** (from `00-phase-overview.md`) —
  `Settings::SessionsController .unscoped` audit conclusion: (a) document and
  keep, (b) fix at `BelongsToTenant`. Default = (a).
- **Q2** (from `00-phase-overview.md`) — `:unprocessable_entity` sweep scope:
  broad (every hit in `app/`) or narrow (just the reviewer-flagged ones).
  Default = broad.

## Follow-ups created

None expected. The four items in this sweep are intentionally narrow. If Q1
flips to (b), the unscoped audit splits out into its own spec under a separate
slug — the architect would write that spec in a follow-up dispatch.

## Decisions (locked)

- **One commit.** All four items ship as a single rails-impl dispatch and a
  single master commit. They do not depend on each other; the bundle is for
  review economy, not technical coupling.
- **No `data-turbo-confirm` reintroduction.** The orphan cleanup is
  removal-only. If a future surface needs a confirm dialog, it goes through
  `ConfirmModalComponent` / the action confirmation page, per the project's hard
  rules.
