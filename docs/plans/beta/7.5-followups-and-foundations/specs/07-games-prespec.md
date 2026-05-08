# Phase 7.5 — Step 07 — Games (pre-spec)

> **PRE-SPEC.** Concept-stage feature. Surfaces what is known, what is unknown,
> and the open questions the user must answer before this doc upgrades into a
> real implementation spec. No code dispatches happen against this doc as-is.
> The master agent does NOT spawn rails-impl or cli-impl agents; the next
> architect-spec dispatch turns the user's answers into a real spec, OR
> explicitly defers to a later phase.

---

## What we have (rooted in code)

The `Game` concept already exists at the model level from Phase 4:

- `games` table (Phase 4):
  `id, tenant_id, collection_id (nullable), title, publisher, platforms (jsonb), timestamps`.
  Source: `docs/plans/beta/04-project-workspace/specs/project-workspace.md`
  §3.3.
- `Game` `belongs_to :collection` (nullable), `has_many :project_references`
  (polymorphic — Phase 4 §4), `has_many :footages`.
- `platforms` is a jsonb array of `{platform, owned, recorded_on}` records, with
  a constrained allowlist (PS5, PS4, Xbox Series, Xbox One, Switch, PC, Mac,
  Mobile).
- Active Storage: `has_one_attached :cover_art`. Variants (thumbnail, card,
  full).
- Polymorphic project references: a `Project` references zero or more `Game`s
  and `Collection`s. Project show page has a "games" pane.
- The `Confirmable::TYPES` allowlist includes `"game"` (per the reviewer
  playbook footage-bulk follow-up's note about which types are supported by
  `/deletions/:type/:ids`).

The `Game` model is implemented and seeded; the show / edit / new flows are
operational; the `_games_pane.html.erb` partial exists on the project show page.

## What is unclear

The user has flagged "Games" as a Phase 7.5 workstream. The model exists, so
"implement Games" is not the ask. The ask is something ELSE — something about
Games that has not yet been specified. From prior context (no documented design
for the new shape):

- A richer Games surface? (E.g. a `/games` index, a Game show page beyond the
  bare Phase-4 default-create.)
- Game metadata sync against an external source (IGDB, MobyGames, GiantBomb)?
- Games as first-class citizens of the YouTube knowledge graph (game ↔ channel ↔
  video relationships)?
- Game playthroughs / sessions tracking?
- Game footage filtering / search anchored on the Game record?
- A pivot to a different Game model entirely (the Phase 4 shape was speculative
  — does the user want to revisit)?

## Open questions

**Q10.a — What does "Games" as a Phase 7.5 workstream mean?** Pick one or
describe a different shape:

- (i) **Richer Games UI.** Today: default-create + edit. Want: a `/games` index,
  a Game show page with cover art + metadata + filtered footage from that game +
  filtered videos that mention it (when video metadata syncs in Phase 8).
- (ii) **External metadata sync.** Pick a source (IGDB / MobyGames / GiantBomb)
  and adapt the existing Voyage / YouTube-OAuth pattern: a `GamesSync` job, an
  audit table, a `Settings → Games` configuration surface.
- (iii) **Games as knowledge-graph nodes.** Tie Games to Channels (a channel is
  "a Mario channel"), tie Games to Videos (a video "is about" Mario Wonder),
  introduce many-to-many tables and a surface for browsing.
- (iv) **Playthrough / session tracking.** A `GameSession` model ties one or
  more Footage rows to a date range against a Game, optionally with notes. The
  user's footage organization story (a-roll / b-roll / commentary) hooks into
  this.
- (v) **Game model rework.** Replace the current model with a different shape.
  (If yes — what shape? What's wrong with the current?)
- (vi) **Something else** — describe.

**Q10.b — Beta scope vs Theta scope.** Whatever Q10.a picks, what fraction is
Beta-scope (this phase or the next) vs Theta-scope (a later phase tied to
multi-user / public release)? E.g. external metadata sync might be Beta;
community-driven Game-tag voting would be Theta.

**Q10.c — Cross-stack surface.** Does the chosen direction touch the `pito` CLI
(a games TUI screen?), MCP tools (a `list_games` tool? a `search_games` tool?),
or both? Or Rails-only?

**Q10.d — Phase ordering.** Does this work block on Phase 8 (data sync), or is
it independent? E.g. tying Games to Videos via metadata REQUIRES Video metadata
to be sync'd, which is Phase 8. External metadata sync against an IGDB-style API
is independent.

## Master agent's lean

**No lean.** The master agent does not have enough context from the prior
conversation log to guess. Tagging this as "open — user answers".

## What happens next

After the user answers Q10.a–d:

- If the answer is "extend / rework existing Games": the next architect-spec
  dispatch produces a real implementation spec under a slug like
  `07b-games-<concrete-shape>.md`. This pre-spec stays as the question record.
- If the answer is "external metadata sync": the spec dispatch produces a
  `07b-games-igdb-sync.md` (or whichever source). The shape mirrors `7a/7b/7c`
  for Google OAuth — a settings surface, a sync job, an audit table.
- If the answer is "defer Games entirely to Phase 9 / 10 / 11": this pre-spec is
  closed with a note pointing at the target phase. The `follow-ups.md` carries
  the deferral.

## Files touched

None in this pre-spec dispatch. Real implementation files come once the
questions are answered and a real spec is dispatched.

## Acceptance

- [ ] User answers Q10.a, Q10.b, Q10.c, Q10.d.
- [ ] Master agent decides: real spec next, or defer to later phase.
- [ ] If real spec: a follow-up architect-spec dispatch produces
      `07b-games-<shape>.md`. This file is closed with a one-line pointer to the
      upgraded spec.
- [ ] If defer: this file is closed with a one-line pointer to the target phase.

## Manual test recipe

Not applicable. Pre-spec — no code lands.

## Cross-stack scope

Decided once Q10.c is answered.

## Follow-ups created

None until the user answers.

## Decisions (locked)

- **Pre-spec, not implementation spec.** No code dispatches off this doc as-is.
- **Phase 4 Games model is settled territory.** This pre-spec does not propose
  ripping out the existing `games` table or the polymorphic project references —
  those work and are seeded. Any rework explicitly enumerates what changes and
  why.
