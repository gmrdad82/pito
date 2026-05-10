# UX sweep — pane-standalone container + double-pane layouts

## Status

**Landed.** Multiple UX fixes across settings, OAuth, channels, videos in one
push. CI green. Awaiting your visual validation in `bin/dev`.

## What changed

### Visual consistency: new `.pane--standalone` modifier

- Added a `.pane--standalone` modifier in `app/assets/tailwind/application.css`
  that drops `.pane`'s fixed 452px width but keeps the pane-look background
  (`--color-pane-bg-a`) + 12px padding. Used as `class="pane pane--standalone"`.
- Replaces the `.framed-block` look on every full-width data-display surface,
  giving consistent pane-bg coloring everywhere data is shown.

### Views switched from `.framed-block` → `.pane.pane--standalone`

- `settings/oauth_applications/{create,show,revoke}.html.erb`
- `settings/tokens/{create,revoke}.html.erb`
- `settings/sessions/revoke.html.erb`
- `doorkeeper/authorizations/{new,show,error}.html.erb`

### OAuth application form helper text

- `settings/oauth_applications/_form.html.erb` redirect-URI hint now shows
  concrete examples:
  - `https://claude.ai/api/mcp/auth_callback` (claude.ai web connector)
  - `http://127.0.0.1:8000/oauth/callback` (native cli / mobile)

### Spacing on label/value tables

- Every label `<td>` in detail tables now has
  `padding-right: 12px; vertical-align: top;` so labels no longer touch values.

### Channels — new + show layout fixes

- `channels/new.html.erb`: input width raised to `60ch` so the canonical 56-char
  YouTube URL placeholder no longer truncates.
- `channels/show.html.erb`: split into a 2-pane row. Left pane: URL + detail
  (starred, connected, last sync). Right pane: videos table. URL uses
  `word-break: break-all` so the full URL is visible instead of truncating.

### Videos — show layout fix

- `videos/show.html.erb`: split into 2 panes inside `.pane-strip`. Detail pane
  (left, 452px) + stats pane (right, 904px via `.pane--wide`). Channel URL wraps
  with `word-break: break-all`.

### Astro website footer

- Reads root `VERSION` file at build time (single source of truth across app +
  website).
- Footer now flows with content, no longer pinned to viewport bottom.

### Phase 8 + Phase 9 + Phase 10

- All three implemented + reviewed + security-audited + prose-rewritten. Reseed
  working. New dev token after Phase 10 reseed:
  `CCvwZcLPGynpEM5SIAKRKjnsQrrqTTe506S-gf-QICs` (save it; only shown once).

## Quality gates

- 1719 RSpec examples → 0 failures.
- Rubocop clean.
- Brakeman clean.
- Prettier clean across all docs.

## Validation steps when you're back

1. `bin/dev` and visit `/settings`. Confirm the index pane-row look feels
   consistent with the other settings detail screens.
2. Visit `/settings/oauth_applications` → click an app → confirm the detail page
   has pane-bg coloring (no longer the lighter framed-block).
3. Visit `/settings/tokens/new` → submit → confirm the post-create reveal page
   has pane-bg.
4. Walk the OAuth consent flow at `/oauth/authorize?...` → confirm the consent
   screen has the pane look.
5. Visit `/channels` → click a channel → confirm 2-pane layout (detail |
   videos), full URL visible.
6. Visit `/videos` → click a video → confirm 2-pane layout (detail | recent
   stats), full URL visible.
7. Visit `/channels/new` → confirm the YouTube URL placeholder is fully visible
   (not truncated).
8. Visit the landing page (`pitomd.com`) → confirm the footer flows with content
   (no longer stuck at viewport bottom).

## Open follow-ups (non-blocking)

- `.framed-block` CSS rule + `docs/design.md` "Framed blocks" section are now
  orphaned. Decision needed: retire entirely vs keep as fallback. Tracked.
- Dependabot alerts (2 moderate) — surface them in Settings → Security on next
  visit; resolve in a hardening pass.

## Beta progress

Roughly 23-25% implemented (3 of 12 work units; specs ready for the remaining 7
non-blocked / non-deferred units). Channel sync (work unit 3) blocked on schema
details from the 7.14 conversation. Phase 12+ implementations queued.
