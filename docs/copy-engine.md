# Copy engine — centralized witty dictionaries

> Status: in progress. Branch `themes` (folded into PR #62; do not merge until the
> user validates). No co-author trailers; no `[skipci]`.

## Sign-off

- [x] Drafted — 2026-06-06
- [ ] Audited — _pending_

## North star

One reusable engine for all user-facing copy. A caller asks for a key; the engine
returns a witty, placeholder-filled line — picking at random when the key has
several variants, or returning the single line when it has one. Whether a place
"uses a dictionary" becomes a **data** choice (one i18n entry vs many), not a code
change, so copy can be grown, shrunk, audited, and kept on-voice in one place.

## Locked decisions

| Topic             | Decision                                                                                                                   |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Engine API        | `Pito::Copy.render(key, vars = {}, variant: nil)` → String. Single entry point for slash, hashtag/reply, chat.             |
| Dictionary = data | An i18n key resolving to a **String** (one line) or an **Array** (variants). Engine treats both the same.                  |
| Always wire       | Callers always go through `Pito::Copy`. "Migrate to/from a dictionary" = edit i18n only (1 entry ⇄ many).                  |
| Voice             | Witty, dry pito voice. Content lives in i18n; voice is enforced by the audit, not by code.                                 |
| Centralized home  | Migrated copy lives under the `pito.copy.*` namespace (`config/locales/pito/copy/*.yml`).                                  |
| Placeholders      | i18n `%{name}` interpolation, filled from `vars`.                                                                          |
| Random + testable | Random variant in prod; a swappable sampler (deterministic in specs) + a `variant:` index override for exactness.          |
| Audit             | `rake pito:copy:audit` lists every `pito.copy.*` key (variant count + placeholders) and flags legacy dictionaries.         |
| Migration         | Move existing dictionaries (theme quips, thinking words, …) onto the engine; then wire fixed replies as 1-entry.           |
| Dictionary size   | **50 variants is the standard** for every dictionary; the audit flags pools below 50. Single-entry copy is enriched to 50. |

## Complexity hints

- `[manual]` — operator/by hand: smoke tests, commits.
- `[low]` — mechanical / established-pattern work.
- `[high]` — architectural / cross-cutting (the engine API, the audit tool).

## Phase index

- P1 — Copy engine core (`Pito::Copy.render`)
- P2 — `pito.copy` namespace + `pito:copy:audit` rake
- P3 — Migrate existing dictionaries onto the engine
- P4 — Always-wire fixed replies (audit + migrate by surface)
- P5 — Standardize every dictionary to 50 variants

---

## P1 — Copy engine core

> `Pito::Copy.render` resolves an i18n key (String or Array), picks a variant
> (random, or a forced index), and interpolates `%{}` placeholders. The single
> seam every caller uses.

- [x] T1.1 `Pito::Copy.render(key, vars = {}, variant: nil)` — resolve `I18n.t(key)`, normalize String|Array → Array, pick (forced `variant` index else via the sampler), interpolate `%{…}` from `vars`; doc-block the contract. complexity: [high]
- [x] T1.2 Define missing-data behavior: missing key surfaces the I18n missing-translation (never a silent `""`); a `%{…}` with no matching var raises a clear error; document both. complexity: [low]
- [x] T1.3 Swappable sampler: `Pito::Copy.sampler` (default random) so specs can force determinism globally; add the RSpec support hook (deterministic sampler in test env). complexity: [low]
- [x] T1.4 Specs: String entry; Array entry (within-set); forced `variant:`; interpolation; missing key raises; missing placeholder raises; single/one-element array. complexity: [low]
- [x] T1.5 Commit: `Copy engine core (Pito::Copy.render: string|array, interpolation, deterministic sampler)`. complexity: [manual]

## P2 — `pito.copy` namespace + audit rake

> A centralized home + a tool to audit copy: variant counts, placeholders, and
> legacy dictionaries still living outside the namespace.

- [x] T2.1 Establish `config/locales/pito/copy/` under `pito.copy.*` as the engine's copy home; document the convention in `AGENTS.md`. complexity: [low]
- [x] T2.2 `rake pito:copy:audit` — list every `pito.copy.*` key with its variant count + placeholder names; mark single-entry vs multi. complexity: [high]
- [x] T2.3 Extend the audit to scan array-valued i18n leaves OUTSIDE `pito.copy.*` and list them as migration candidates. complexity: [low]
- [x] T2.4 Specs: audit output (counts, placeholder extraction, legacy-candidate detection) against a fixture locale. complexity: [low]
- [x] T2.5 Commit: `pito.copy namespace + pito:copy:audit rake`. complexity: [manual]

## P3 — Migrate existing dictionaries

> Move the dictionaries that already exist onto the engine + namespace, behavior
> unchanged. Use the P2 audit to find them all.

- [x] T3.1 Migrate the theme apply quips (`Pito::Themes::Quips` + `pito.hashtag.theme.apply.quips`) to `Pito::Copy` + `pito.copy.theme.applied`. complexity: [low]
- [x] T3.2 Migrate the thinking-word dictionaries (the `emit_thinking(dictionary:)` source) to `Pito::Copy` + `pito.copy.thinking.*`. complexity: [low]
- [x] T3.3 Migrate any other array-valued copy the audit surfaces to the engine + namespace. complexity: [low]
- [x] T3.4 Specs: migrated callers still pass; audit reports them under `pito.copy.*` with zero remaining legacy candidates from this set. complexity: [low]
- [x] T3.5 Commit: `Migrate existing dictionaries onto the copy engine`. complexity: [manual]

## P4 — Always-wire fixed replies (audit + migrate by surface)

> The big sweep (user-approved): route fixed single-line replies through the
> engine as one-entry dictionaries, so any of them can grow variants later with no
> code change. Large but mostly mechanical.

- [x] T4.1 Audit slash-command fixed replies (confirmations / errors / usages) and list engine-wiring candidates. complexity: [low]
- [x] T4.2 Wire slash replies through `Pito::Copy.render` (single-entry dictionaries). complexity: [low]
- [x] T4.3 Wire hashtag / follow-up replies + errors through the engine. complexity: [low]
- [x] T4.4 Wire free-form chat fixed copy through the engine. complexity: [low]
- [x] T4.5 Specs across the migrated surfaces. complexity: [low]
- [x] T4.6 Commit: `Wire command/reply/chat copy through the engine (single-entry dictionaries)`. complexity: [manual]

## P5 — Standardize every dictionary to 50 variants

> Decision: **50 is the standard size** for every dictionary. Relocate the 13
> single-entry wired keys under `pito.copy.*` and enrich each to 50; top up the
> existing sub-50 pools to 50. Voice: mirror the existing 50-entry pools (dry,
> witty pito). Placeholders preserved exactly. Deterministic-first test sampler
> keeps specs stable. (`youtube.ascii_art` is multi-line art — keep additions
> small, consistent-width, tasteful; quality over filler.)

- [x] T5.1 Relocate the 13 single-entry wired keys to `pito.copy.*` (new keys + update each `Pito::Copy.render` call site + move/remove old YAML), still 1-entry; suite green. complexity: [low]
- [x] T5.2 Enrich auth/confirmation/connect copy to 50 each (`not_enrolled`, `confirmation.confirmed/cancelled/execution_failed`, `connect.not_configured`). complexity: [low]
- [x] T5.3 Enrich disconnect copy to 50 each (`confirmation.body` %{handle_html}, `confirmation.cancelled` %{handle}, `errors.already_gone/missing_target/not_found` %{target}). complexity: [low]
- [x] T5.4 Enrich help/theme copy to 50 each (`help.body`, `theme.list.intro`, `theme.sidebar.placeholder`). complexity: [low]
- [ ] T5.5 Top up `pito.copy.theme.applied` 25 → 50 (%{theme}). complexity: [low]
- [ ] T5.6 Top up `pito.copy.thinking.confirmation.doing` + `.done` 10 → 50 as INDEX-ALIGNED pairs. complexity: [low]
- [ ] T5.7 Top up `pito.copy.youtube.ascii_art` 20 → 50 (small, consistent-width arts). complexity: [low]
- [ ] T5.8 Extend `pito:copy:audit` to flag any `pito.copy.*` pool below 50 ("below standard") + spec it; full suite green. complexity: [low]
- [ ] T5.9 Commit (per cohesive group): relocate, enrich, top-ups, audit. complexity: [manual]

## How to use this plan

Execute P1 → P4 sequentially (each green + committed). Decisions: engine is
`Pito::Copy`; copy lives under `pito.copy.*`; sampling is uniform random.
