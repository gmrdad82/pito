# Themes — multi-theme system + `/theme` command

> Status: in progress. Branch `themes` (no worktrees, sequential). PR #62 — **do
> not merge until the user validates**. No co-author trailers; no `[skipci]`.

## Sign-off

- [x] Drafted — 2026-06-06
- [ ] Audited — _pending_

## North star

`/theme` lets you switch among 18 light/dark themes — a preview sidebar, a
listed System message with `#preview`/`#apply` follow-ups, and direct
`/theme apply <name>`. Themes are data-driven (one Ruby file each → loader →
rake-generated CSS), global via `AppSetting`, and **every theme keeps pito brand
blue (`--brand-pito` #5170ff)**; only the other tokens change. Tokyo Night stays
the unaltered default.

## Locked decisions

| Topic                                           | Decision                                                                                           |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Command                                         | `/theme` (singular) for everything                                                                 |
| Engine                                          | one Ruby file per theme → registry/loader → `rake pito:themes:export` → committed `themes.css`     |
| Shades                                          | auto-derive surface/elevated, fg-dim/faded, borders via `mix()`; per-theme overrides allowed       |
| Default                                         | Tokyo Night, **unaltered**; Dracula + the other 16 are extra                                       |
| pito blue                                       | `--brand-pito` #5170ff — identical on every theme                                                  |
| Persistence                                     | global via `AppSetting.theme` + `#pito-settings` + `broadcast_global_settings_update`              |
| `/theme` (bare)                                 | opens the preview sidebar (↑/↓ preview, Enter apply, Esc revert, current marked, witty hint)       |
| `/theme list` (alias `ls`)                      | does NOT open the sidebar — lists themes in a **System message** with `#preview`/`#apply` hints    |
| `#preview <name>` / `#apply <name>`             | hashtag **replies** (follow-ups to the list message) — preview/apply that theme                    |
| `/theme preview <name>` / `/theme apply <name>` | distinct slash subcommands (same effect as the hashtags, but are commands, not replies)            |
| `/theme <name>`                                 | shorthand → apply that theme                                                                       |
| default / reset                                 | `default` resolves to Tokyo Night; `/theme reset` → reset to default; preview/apply `default` work |
| Aliases                                         | real slash alias system; first one shipped: `list` ↔ `ls`; production-ready                        |
| Branch / merge                                  | branch `themes`, no worktrees, sequential; squash-merge at the end after validation                |
| Specs                                           | Rails + JS (Vitest) — including the alias, the hashtag replies, and the rake task                  |

## Complexity hints

- `[manual]` — operator/by hand: smoke tests, commits, the GitHub PR.
- `[low]` — mechanical / established-pattern work.
- `[high]` — architectural / cross-cutting (DSL, command routing, alias system).

## Phase index

- P0 — Setup (branch + doc + PR) — **done**
- P1 — Theme engine core (Mix / Definition / Registry) — **done**
- P2 — CSS generation (generator + rake + wire-in) — **done**
- P4 — Persistence (AppSetting.theme + data-theme + endpoint) — **done**
- P3 — The 16 remaining theme palettes + regenerate
- P5 — `/theme` command core (subcommands, vocab, autocomplete, --help)
- P5.5 — Argument-arity validation + autocomplete stop (general command fix)
- P6 — Slash alias system (`list` ↔ `ls`)
- P7 — `/theme list` System message + `#preview`/`#apply` hashtag replies
- P8 — `/theme` (bare) preview sidebar
- P9 — Preview/apply JS (`theme_nav_controller`) + Vitest
- P10 — Light-theme hardcoded-color audit + fix
- P11 — Finalize (full suite green, PR ready)

---

## P0 — Setup _(done)_

- [x] T0.1 Create branch `themes` off `main`. complexity: [manual]
- [x] T0.2 Write `docs/themes.md` (this plan). complexity: [low]
- [x] T0.3 Open PR #62 (base `main`), marked do-not-merge. complexity: [manual]
- [x] T0.4 Commit: `Plan: themes — multi-theme system + /theme command`. complexity: [manual]

## P1 — Theme engine core _(done)_

- [x] T1.1 `Pito::Themes::Mix` — port the `mix(a, b, t)` hex-blend from `app/services/pito/theme.rb`; doc-block. complexity: [low]
- [x] T1.2 `Pito::Themes::Definition` — resolve a raw `{slug,label,mode,base,overrides}` into the full token set; auto-derive surface/elevated/dim/faded/borders; overrides win; `brand_pito` constant; doc-block. complexity: [high]
- [x] T1.3 `Pito::Themes::Registry` — self-registering loader (`all`/`find`/`names`/`grouped`/`default`); doc-block. complexity: [low]
- [x] T1.4 `definitions/tokyo_night.rb` — migrate the existing values EXACTLY (overrides). complexity: [low]
- [x] T1.5 `definitions/dracula.rb` — canonical Dracula palette. complexity: [low]
- [x] T1.6 Specs: `mix_spec`, `definition_spec`, `registry_spec` (incl. tokyo-night exact-migration guard). complexity: [low]
- [x] T1.7 Commit: `P1: theme engine core (Mix/Definition/Registry) + tokyo-night + dracula`. complexity: [manual]

## P2 — CSS generation _(done)_

- [x] T2.1 `Pito::Themes::CssGenerator` — ERB → `:root` (default tokens) + one `[data-theme="<slug>"]` block per theme; `--brand-pito` in every block; doc-block. complexity: [high]
- [x] T2.2 Rake `pito:themes:export` → writes `app/assets/tailwind/themes.css` (generated header). complexity: [low]
- [x] T2.3 `@import "./themes.css";` in `application.css`; remove the hand-written `[data-theme="tokyo-night"]` block. complexity: [low]
- [x] T2.4 Run the export + confirm `bin/rails tailwindcss:build` compiles. complexity: [low]
- [x] T2.5 Specs: generator output (tokyo-night/dracula blocks, brand-pito constant) + rake export writes the file. complexity: [low]
- [x] T2.6 Commit: `P2: theme CSS generator + pito:themes:export rake + wire themes.css`. complexity: [manual]

## P4 — Persistence _(done)_

- [x] T4.1 `AppSetting.theme` / `theme=` (key `"theme"`, default `"tokyo-night"`) + spec. complexity: [low]
- [x] T4.2 Layout: dynamic `<html data-theme="<%= AppSetting.theme %>">` + `data-theme` on `#pito-settings`. complexity: [low]
- [x] T4.3 Broadcaster: include `data-theme` in the `#pito-settings` strings (instance + global). complexity: [low]
- [x] T4.4 `settings.js`: `currentTheme()` reader (`#pito-settings` → `<html>` fallback). complexity: [low]
- [x] T4.5 `PATCH /settings/theme` → `SettingsController#theme` (Registry-validated, 422 on unknown, global broadcast) + route. complexity: [low]
- [x] T4.6 Specs: `AppSetting.theme` default/persist; request spec (persist + broadcast + unknown→422 + auth). complexity: [low]
- [x] T4.7 Commit: `P4: theme persistence: AppSetting.theme + dynamic data-theme + endpoint`. complexity: [manual]

---

## P3 — The 16 remaining theme palettes

> One definition file per theme under `app/services/pito/themes/definitions/`
> (base bg/fg + 7 accents; overrides only where a palette has canonical
> surface/elevated/border values). Palettes from terminalcolors.com / canonical
> sources. After all files: regenerate + assert completeness.

- [x] T3.1 `one_dark.rb` (Atom One Dark, mode :dark). complexity: [low]
- [x] T3.2 `one_light.rb` (Atom One Light, mode :light). complexity: [low]
- [x] T3.3 `gruvbox_dark.rb` (mode :dark). complexity: [low]
- [x] T3.4 `gruvbox_light.rb` (mode :light). complexity: [low]
- [x] T3.5 `nord.rb` (mode :dark). complexity: [low]
- [x] T3.6 `github_dark.rb` (mode :dark). complexity: [low]
- [x] T3.7 `github_light.rb` (mode :light). complexity: [low]
- [x] T3.8 `catppuccin_mocha.rb` (dark). complexity: [low]
- [x] T3.9 `catppuccin_latte.rb` (light). complexity: [low]
- [x] T3.10 `ayu_dark.rb` (dark). complexity: [low]
- [x] T3.11 `ayu_light.rb` (light). complexity: [low]
- [x] T3.12 `ayu_mirage.rb` (dark). complexity: [low]
- [x] T3.13 `solarized_dark.rb` (dark). complexity: [low]
- [x] T3.14 `solarized_light.rb` (light). complexity: [low]
- [x] T3.15 `tomorrow_night.rb` (dark). complexity: [low]
- [x] T3.16 `tomorrow.rb` (Tomorrow, light). complexity: [low]
- [x] T3.17 Run `rake pito:themes:export`; commit the regenerated `themes.css`. complexity: [low]
- [x] T3.18 Spec: every `Registry.all` theme resolves a complete token set + `brand_pito == #5170ff`; `grouped` has the right dark/light split (18 total). complexity: [low]
- [x] T3.19 Confirm `bin/rails tailwindcss:build` compiles with all 18 blocks. complexity: [low]
- [x] T3.20 Commit: `P3: 16 remaining theme palettes + regenerate themes.css`. complexity: [manual]

## P5 — `/theme` command core

> Handler with subcommands `list`/`ls`/`preview`/`apply`/`reset` + a bare theme
> name (= apply). `default` resolves to Tokyo Night. `--help`. Autocomplete from
> a dynamic `theme_names` vocab. (The sidebar + list-message + hashtag replies
> are P7/P8; this phase wires the command spine + the apply/preview/reset paths.)

- [x] T5.1 `Pito::Themes::Registry.names` + a `resolve_target(token)` helper that maps a slug OR `"default"` → a Definition (nil if unknown). complexity: [low]
- [x] T5.2 Dynamic vocabulary `theme_names` (slugs + `default`) backed by the registry; register it in `Vocabularies`/`Registry`. complexity: [high]
- [x] T5.3 `Pito::Slash::Handlers::Theme` skeleton: `verb = :theme`, `description_key`, `grammar do … end` (a `subcommand`/`name` slot from `theme_names` + the subcommand keywords), auth gate. complexity: [high]
- [x] T5.4 Parse the first arg: subcommand (`list/ls/preview/apply/reset`) vs theme name vs empty; dispatch accordingly. complexity: [high]
- [x] T5.5 `apply` path: `AppSetting.theme = slug` → broadcast → System confirm (witty i18n). Covers `/theme apply <name>`, `/theme <name>`. complexity: [low]
- [x] T5.6 `reset` path: apply the default (Tokyo Night) + confirm. complexity: [low]
- [x] T5.7 `preview` path (no sidebar): apply-for-this-render semantics — emit a System message instructing how to keep it (or persist on confirm). Decide preview-vs-apply persistence and document inline. complexity: [high]
- [x] T5.8 Unknown target → witty error (i18n) listing valid names / pointing to `/theme list`. complexity: [low]
- [x] T5.9 `--help`: per-command usage + a grouped theme list via `HelpRenderer`/`show_help` (i18n). complexity: [low]
- [x] T5.10 i18n: `pito.slash.theme.*` (descriptions, help usage/description, confirmations, errors) — witty voice. complexity: [low]
- [x] T5.11 Autocomplete: `/the…`→`/theme`; `/theme <partial>` ghost/menu from `theme_names`; subcommands suggested. complexity: [low]
- [x] T5.12 List `/theme` in `/help` sections + the ctrl+k command palette (i18n). complexity: [low]
- [x] T5.13 Specs: handler (apply/reset/preview/unknown/default), request spec (apply persists + broadcasts), grammar + autocomplete (theme_names), `--help`. complexity: [low]
- [x] T5.14 Commit: `P5: /theme command core (apply/preview/reset + vocab + autocomplete + --help)`. complexity: [manual]

## P5.5 — Argument-arity validation + autocomplete stop (general command fix)

> Reported during theme testing but general: commands silently accept excess
> arguments (`/theme ayu-dark ayu-dark`, `/help --help --help`) and the
> autosuggest re-offers a filled single slot forever. Enforce grammar arity at
> dispatch + stop suggesting once slots are full. Cross-cutting — must not
> regress config (repeatable kv), disconnect (free target), or flag commands.

- [x] T5.5.1 Autocomplete: in `engine.rb#find_active_slot_with_context`, when all non-repeatable slots are filled return NO active slot (drop the `|| eligible_slots(...).last` fallback); repeatable/kv paths unchanged. complexity: [high]
- [x] T5.5.2 Spec: `/theme ayu-dark ` → no further suggestions; `/config google k=v ` still suggests keys (repeatable). complexity: [low]
- [x] T5.5.3 Dispatcher arity guard: reject an invocation with more positional args than its grammar spec can consume (no repeatable/`free` slot to absorb) → witty "too many arguments" error (i18n); skip specless commands. complexity: [high]
- [x] T5.5.4 Audit every command (config/disconnect/help/login/logout/connect/new/resume/theme + chat/hashtag) so valid forms still pass; decide + handle `/help --help --help` (extra flags) sensibly; document. complexity: [high]
- [x] T5.5.5 Specs: `/theme x y` → invalid; `/theme x` → valid; representative excess-arg cases per command shape; full suite green. complexity: [low]
- [x] T5.5.6 Commit: `Reject excess command arguments + stop autocomplete after slots filled`. complexity: [manual]

## P6 — Slash alias system (`list` ↔ `ls`)

> Production-ready alias mechanism for slash commands; first alias shipped:
> `/theme ls` ≡ `/theme list`. (Leverage the grammar `Spec.aliases` /
> `specs_for_alias` infra; extend to subcommand-keyword aliasing if needed.)

- [x] T6.1 Decide + implement the alias surface: `ls` as an alias of the `list` subcommand (vocabulary synonym OR spec alias — pick the production-correct one and doc-block it). complexity: [high]
- [x] T6.2 Wire the alias so the dispatcher routes `/theme ls` → the list path. complexity: [low]
- [x] T6.3 Autocomplete/help reflect the alias (or intentionally hide `ls` — document the choice). complexity: [low]
- [x] T6.4 Specs: `/theme ls` behaves identically to `/theme list`; the alias is registered/resolvable; an alias-mechanism unit spec. complexity: [low]
- [x] T6.5 Commit: `P6: slash alias system + /theme ls alias of /theme list`. complexity: [manual]

## P7 — `/theme list` System message + `#preview`/`#apply` hashtag replies

> `/theme list` (and `ls`) emits a System message listing themes grouped
> Dark/Light, with hints to follow up via `#preview <name>` / `#apply <name>`.
> Those hashtags are reply commands that preview/apply, mirroring P5's logic.

- [x] T7.1 `list` path builds a System message: themes grouped Dark/Light (kv-style rows: slug + label), current theme marked. complexity: [low]
- [x] T7.2 Append follow-up affordance to that message: `#preview <name>` / `#apply <name>` hints (witty i18n). complexity: [low]
- [x] T7.3 `Pito::Hashtag::Handlers` — a handler resolving `#preview <name>` and `#apply <name>` (reuse P5's resolve_target + apply/preview). complexity: [high]
- [x] T7.4 Hashtag grammar/vocab: `preview`/`apply` stems + `theme_names` arg; register. complexity: [low]
- [x] T7.5 i18n for the list message + hashtag confirmations/errors. complexity: [low]
- [x] T7.6 Specs: `/theme list` (+ `ls`) renders the grouped System message; `#preview <name>` previews; `#apply <name>` applies (persist) — reply paths. complexity: [low]
- [x] T7.7 Commit: `P7: /theme list System message + #preview/#apply hashtag replies`. complexity: [manual]

## P8 — `/theme` (bare) preview sidebar

> Bare `/theme` opens the right-side sidebar (mirror `/resume`), themes grouped
> Dark/Light, current theme marked with a cursor, witty subtitle hint.

- [x] T8.1 `Pito::Sidebar::Themes::Component` (`groups`, `current_theme`) — reuse `Sidebar::Component` + `Section::SectionHeaderComponent`. complexity: [low]
- [x] T8.2 `themes/_row.html.erb` — `.pito-theme-row[data-theme-name]`, label, current marker/cursor (`is-current`). complexity: [low]
- [x] T8.3 `chat/_theme_sidebar.turbo_stream.erb` (or themes view) — `turbo_stream.update "pito-sidebar"` wrapping the component + the witty subtitle hint ("↑/↓ preview · Enter apply"). complexity: [low]
- [x] T8.4 Bare `/theme` path renders the sidebar turbo_stream (mirror `chat#handle_resume`). complexity: [low]
- [x] T8.5 i18n: sidebar title + hint. complexity: [low]
- [x] T8.6 Specs: component (grouping + current marker) + request (`/theme` returns the sidebar turbo_stream targeting `pito-sidebar`). complexity: [low]
- [x] T8.7 Commit: `P8: /theme preview sidebar (grouped, current marker, hint)`. complexity: [manual]

## P9 — Preview/apply JS (`theme_nav_controller`) + Vitest

- [x] T9.1 `theme_nav_controller.js` (mirror `resume_controller`/`notifications_nav`): ↑/↓ move highlight + `document.documentElement.dataset.theme = slug` (live preview); current-theme marker. complexity: [high]
- [x] T9.2 Enter → apply: PATCH `/settings/theme {theme:slug}` (CSRF), keep the preview, update the current marker. complexity: [low]
- [x] T9.3 Esc / `disconnect` without apply → revert `data-theme` to the persisted theme (`currentTheme()`); clear the sidebar. complexity: [high]
- [x] T9.4 `node --check`; Vitest spec: arrow sets `data-theme`; Enter PATCHes; disconnect reverts; highlight/current marker. complexity: [low]
- [x] T9.5 Commit: `P9: theme preview/apply JS (theme_nav_controller) + Vitest`. complexity: [manual]

## P10 — Light-theme hardcoded-color audit + fix

- [x] T10.1 Grep components + CSS for literal hex / non-token color utilities (`text-[#…]`, raw `#…` in ERB/CSS, fixed `bg-*`/`text-*` that should be tokens). complexity: [low]
- [x] T10.2 Route the offenders through semantic tokens; confirm `--brand-pito` is the ONLY constant color (same on every theme). complexity: [low]
- [ ] T10.3 Spot-check a light theme (e.g. github-light) renders readable: chatbox, segments, sidebar, palette, mini-status. complexity: [manual]
- [x] T10.4 Adjust/add specs where a token hook changed. complexity: [low]
- [x] T10.5 Commit: `P10: route hardcoded colors through tokens (light-theme readiness)`. complexity: [manual]

## P11 — Finalize

- [ ] T11.1 Full `bundle exec rspec` green. complexity: [manual]
- [ ] T11.2 `npm test` green; `bin/rubocop` clean; `prettier --write` on `docs/themes.md`. complexity: [manual]
- [ ] T11.3 Smoke: `/theme` sidebar (↑/↓ preview, Enter apply, Esc revert, current marked); `/theme list` + `ls` System message + `#preview`/`#apply`; `/theme apply one-dark`; `/theme reset`; `/theme --help`; reload persists; pito blue constant; light themes readable. complexity: [manual]
- [ ] T11.4 PR #62 CI green; **await user validation — do not merge**. complexity: [manual]

## Per-phase Definition of Done

Doc-blocks on new classes (contract on base, specifics on extenders); new +
edge-case specs (Rails + JS where applicable); `bundle exec rspec` + `npm test` +
`bin/rubocop` + `node --check` green; each phase's `Commit:` task stages the plan
file alongside the work and flips its tasks `[ ] → [-] → [x]` per transition; push;
PR CI (`rails`/`js`/`prettier`) green.
