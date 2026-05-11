# ADR 0008 — Shared `StatusBadgeComponent` and per-domain `RatingBadgeComponent`

## Status

Accepted, 2026-05-12. [skipci]

## Context

Pito's UI grew several small "colored pill" surfaces over the last few phases:

- Phase 16 (Notifications) introduced `.notification-severity-badge` — a
  hand-rolled CSS class with four severity-color selectors
  (`info` / `success` / `warn` / `urgent`).
- Phase 15 (Calendar) introduced `.calendar-badge--all-day` — a separate
  one-off class for the calendar's all-day marker.
- Phase 14 (Game model) introduced a per-game rating tier — a six-color spread
  (`s-tier` / `a-tier` / `b-tier` / `c-tier` / `d-tier` / `f-tier`) rendered
  inline in game tiles and on the game show page.
- Phase 25 (Login security) wanted yes / no markers on the new-location
  approval table and the audit log surfaces.
- Phase 27 (Games listing) wanted ownership badges per-platform and a way to
  surface "owned" / "not owned" / "tracked" with consistent visual weight
  across tiles and list mode.

Each surface re-invented the same shape: a small monospaced pill, a colored
left-strip or full background tint, a label inside `[brackets]`. The CSS for
each lived in a different section of `app/assets/tailwind/application.css`,
the markup lived inline in the respective ERB partials, and the color tokens
were declared ad-hoc per surface. Adding a new badge kind required editing
two or three files plus the design doc.

A cross-cutting cleanup pass during the beta2 polish wave (2026-05-11)
consolidated these into two ViewComponents — one for the cross-cutting
"status" axis (info / success / warn / urgent / yes / no / all-day) and a
second per-domain component for the six-tier game rating spread that is
genuinely game-specific.

## Decision

Introduce two ViewComponents and migrate the existing badge surfaces onto
them.

### `StatusBadgeComponent` — cross-cutting status badges

Single component at `app/components/status_badge_component.{rb,html.erb}`
that takes:

- `kind:` — one of `:info`, `:success`, `:warn`, `:urgent`, `:yes`, `:no`,
  `:all_day`. The enum is closed; adding a new kind requires touching the
  component (intentional friction so new color choices route through the
  design owner).
- `label:` — the text inside the `[brackets]`.
- Optional content slot for cases where the label is composed dynamically.

The component renders a `<span class="status-badge status-badge--<kind>">`
wrapper. Colors are CSS-variable-driven — the component reads
`--status-badge-<kind>-bg` and `--status-badge-<kind>-fg` from the design
token table in `app/assets/tailwind/application.css`. Theme overrides flow
through the variable layer, not the component markup.

Migrations from ad-hoc classes:

- `.notification-severity-badge.info` → `StatusBadgeComponent.new(kind:
  :info)`.
- `.notification-severity-badge.success` → `kind: :success`.
- `.notification-severity-badge.warn` → `kind: :warn`.
- `.notification-severity-badge.urgent` → `kind: :urgent`.
- `.calendar-badge--all-day` → `kind: :all_day`.
- New `yes` / `no` kinds power the new-location-approval table, the
  per-platform-ownership row in `/games`, and any future boolean-axis
  surface.

### `RatingBadgeComponent` — game rating tier badges (per-domain)

Separate component at `app/components/rating_badge_component.{rb,html.erb}`
that takes `tier:` (`:s` / `:a` / `:b` / `:c` / `:d` / `:f`) and an
optional `label:` override (default: the tier letter). Renders
`<span class="rating-badge rating-badge--<tier>">`. Colors are CSS-variable
driven the same way StatusBadge is (`--rating-badge-<tier>-bg` /
`--rating-badge-<tier>-fg`).

Kept separate from `StatusBadgeComponent` because:

- The six-tier color spread is game-specific (S/A/B/C/D/F is a games
  taxonomy, not a cross-cutting status axis).
- Mixing it into `StatusBadgeComponent` would balloon the closed enum and
  forced every consumer to know about color choices irrelevant to its
  surface.
- The visual weight differs — rating badges sit inside the game tile cover
  art region; status badges sit inline in copy.

## Consequences

- **One source of truth per badge surface.** Adding a new status kind means
  declaring a CSS variable pair and adding the enum case in
  `StatusBadgeComponent`. Adding a new game rating tier means the same in
  `RatingBadgeComponent`. The ERB call site stays a one-liner.
- **Theme-ready out of the box.** Color choices live in CSS variables, not
  hardcoded values. A future dark theme overrides the variables once; every
  badge updates.
- **Removed CSS:** `.notification-severity-badge` + its four selectors and
  `.calendar-badge--all-day` were dropped from
  `app/assets/tailwind/application.css`. Tailwind rebuild emitted a clean
  diff.
- **Migration cost:** every existing badge call site was updated in the same
  wave. ERB partials touched: notification list / detail, calendar entry
  pill, game tile, game show, security pages, settings auto-block table.
- **Specs:** per-component spec at
  `spec/components/status_badge_component_spec.rb` and
  `spec/components/rating_badge_component_spec.rb` (render gate, every
  enum value, hard-rule sweep including no JS confirm tokens).

## Open questions (deferred)

- Should the rating badge component be lifted into a generic `TierBadge`
  surface when a second tier-based domain (e.g. "viewer engagement
  classification") ships? Likely yes — the tier-letter shape is reusable.
  Defer until the second consumer arrives so the abstraction is justified
  by two real examples, not one.
- Status kinds may grow if a future surface needs e.g. `:neutral` or
  `:paused`. The closed enum is intentional friction; add the case when
  a real call site asks for it.

## Alternatives considered

- **Single `BadgeComponent` with a free-form `color:` kwarg.** Rejected.
  Free-form color choices defeat the design-token consolidation and let
  every consumer pick its own shade. The closed enum is the point.
- **Keep badges as CSS classes + ERB helpers (`status_badge(kind:,
  label:)`).** Rejected. Helpers don't participate in the
  `BracketedLinkComponent` family the rest of the app uses;
  ViewComponents do. Consistency with the bracketed-link surface
  matters more than the small helper / component delta.
- **Inline-rendered SVG badges.** Rejected. SVG is overkill for a
  text-pill surface; the CSS-driven span is simpler, accessible
  (screen readers read the label text directly), and copy-paste-able.

## Date

2026-05-12. [skipci]

## Related

- `app/components/status_badge_component.rb` — the cross-cutting badge
  component.
- `app/components/rating_badge_component.rb` — the game-tier badge
  component.
- `app/assets/tailwind/application.css` — `--status-badge-*` and
  `--rating-badge-*` CSS variable tables.
- `docs/design.md` → "Bracketed links / buttons" — sibling convention.
  Update this doc to add a "Status badges" section once the component
  family stabilizes through one more dispatch.
- `docs/plans/beta/16-notifications/log.md` — origin of the
  `.notification-severity-badge` class the migration retired.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/log.md` —
  RatingBadge call sites in games tile + list mode + show.
