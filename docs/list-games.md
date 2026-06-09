# list games — table, platforms, release date, suggestions

> Status: Running (plan-runner) — current branch `cleanup-fixups`.

## Sign-off

- [x] Drafted
- [x] Audited

## Context

`list games` is the games-domain list command in the conversational shell. Four
problems, all traced to root cause in the current branch:

1. **Multi-column table collapses to a vertical list.** `list games with developer,
   publisher, genres, release date, year, platforms` renders each header on its own
   line instead of a table. Root cause: `Pito::Event::SystemComponent#table_grid_cols`
   builds a Tailwind arbitrary class at *runtime* (`grid-cols-[max-content_…_1fr]`).
   Tailwind v4 only compiles classes it scans in source (`@source "../../components"`);
   the only literal in source is the 2-col `grid-cols-[max-content_1fr]`. Any N≥3 string
   is never compiled → the element keeps `display:grid` with **no** `grid-template-columns`
   → one implicit column → vertical stack. User wants columns that **wrap** and stay
   compact — not `max-content` columns that expand to full content width.

2. **Platforms show raw IGDB names.** The platform column joins `g.platforms` verbatim →
   "Google Stadia, Xbox Series X|S, PlayStation 4, Nintendo Switch 2, PC (Microsoft
   Windows)…". User wants ONLY 3 pito tokens, labelled **PlayStation / Switch / Steam**
   (Xbox/Google/Mac/PC names dropped). A working token mapping already exists but is
   private to the detail card (`app/components/pito/game/detail_component.rb:13-69`,
   `IGDB_TO_TOKEN` + `platform_tokens`/`platforms_label`). Raw names stay stored; only
   display + sort normalize.

3. **Release date column isn't routed through a formatter.** User wants it formatted via
   `Pito::Formatter` like "June 09, 2026". `Game#release_label` (`app/models/game.rb:76-97`)
   already produces this for full-precision dates (and partial labels / "TBA" otherwise)
   but the logic lives in the model, not in the `Pito::Formatter::*` family of pure
   functions.

4. **Autocomplete is wrong after `list games`.** After `list games ` the ghost should be
   ` with` but the user sees "channels"; `list games with ` offers no fields. Root cause:
   the server engine *does* compute clause ghosts (`Pito::Suggestions::ListClauseGhost`)
   but the JS client never defers to it for the `list` verb — `_computeLocalGhost` resolves
   the static `:noun` slot locally (`app/javascript/controllers/pito/suggestions_controller.js:583-653`).
   And nothing suggests the ` with` connector after the noun (`ListClauseGhost.ghost`
   returns nil unless a `with`/`sorted by` clause is already present). The `with` options
   must be exactly platform|platforms, genre|genres, developer|dev, publisher, release
   date, year — **no channels** in the `with` list (`ListClauseGhost.registry_for` already
   excludes channels). The bare `list ` "channels" default is fine and stays. Channel
   filtering is the separate Shift+Tab handle mechanism (`chat_form_controller.js`), out of
   scope. Videos/channels suggestions are a later session — focus is `list games`.

Outcome: clean wrapping multi-column table; platforms shown as PlayStation/Switch/Steam
only; release date via a `Pito::Formatter`; and `list games` autocomplete that ghosts
` with` then the field tokens, never "channels". Specs added in both Rails (RSpec) and JS
(vitest).

## North star

`list games with developer, publisher, genres, release date, year, platforms` renders a
compact, word-wrapping table; platform cells read "PlayStation, Switch, Steam"; release
dates read "June 09, 2026"; and the input ghosts ` with` → field tokens as you type.

## Locked decisions

- **Reuse the existing mapping — don't reinvent.** The detail card already has the working
  mechanism: `IGDB_TO_TOKEN` (an `[regex, token]` array) + `#platform_tokens` +
  `#platforms_label` (`app/components/pito/game/detail_component.rb:13-69`). We **extract
  that verbatim** into a shared module and **broaden the existing regexes** in place — same
  array shape, same method semantics.
- **Platform labels:** `ps → PlayStation`, `switch → Switch`, `steam → Steam`. Three buckets,
  matched case-insensitively against each raw IGDB name (broadened `IGDB_TO_TOKEN` entries):
  - **PlayStation** ← `/playstation|ps\s?\d/i` (PS5, PS4, PlayStation 3, Playstation 4, …).
  - **Switch** ← `/switch/i` (Nintendo Switch, Switch 2, Switch Gen 1, …).
  - **Steam** (PC bucket) ← `/steam|pc|windows|gog|epic|amazon|battle\.?net/i`.
  Everything else is **dropped** from display — Xbox*, Google Stadia, Mac, etc. Generation-
  specific labels rejected (buckets are coarse).
- **Platforms stored unchanged.** Only display + the platform sort key normalize.
- **Table grid uses a CSS class + a `data-cols` attribute** (like `data-accent`) selecting
  static, compiled `.pito-data-grid[data-cols="N"]` rules. **No inline style, no runtime
  Tailwind arbitrary classes.** First two columns (`#`, Game/key) are content-sized
  defaults; every extra `with` column is an equally-spaced, wrap-capable `1fr` track.
- **Single source of truth for `list` ghosts is the server.** The JS client defers the whole
  `list` verb to `POST /suggestions` (returns `null` from `_computeLocalGhost`); the server's
  `ListClauseGhost` + `compute_ghost` drive noun completion, the ` with` connector, the
  `with`/`sorted by` field tokens, and channel exclusion.
- **Noun vocab order unchanged** (`%w[channels videos games]` — natural to the user). The bare
  `list ` default ghost stays "channels"; that is acceptable. Scope is `list games` only —
  videos/channels suggestions are a later session.
- Plan tiers `[manual|low|high]`; no `[skipci]`; current branch (`cleanup-fixups`); specs on;
  plain imperative commit messages, no co-author trailer.

## Phase index

- **Phase 1 — Platform tokens (display + sort), PlayStation/Switch/Steam**
- **Phase 2 — Release date via `Pito::Formatter`**
- **Phase 3 — Wrapping multi-column table grid**
- **Phase 4 — `list games` autocomplete: ` with` connector + field tokens**
- **Phase 5 — Help message rewrite + `list games --help`**

---

## Phase 1 — Platform tokens (display + sort)

- [x] T1.1 Create `docs/list-games.md` with this file's full content. complexity: [manual]
- [x] T1.2 Move the existing `IGDB_TO_TOKEN` array, `#platform_tokens`, and `#platforms_label` verbatim out of `detail_component.rb` into new `app/services/pito/game/platform_tokens.rb` (module `Pito::Game::PlatformTokens`, `module_function`), keeping the `[regex, token]` shape; methods take `platforms` instead of reading `@game`. complexity: [low]
- [x] T1.3 Broaden the moved `IGDB_TO_TOKEN` regexes in place to the three buckets (Locked decisions): PlayStation `/playstation|ps\s?\d/i`, Switch `/switch/i`, Steam `/steam|pc|windows|gog|epic|amazon|battle\.?net/i`. complexity: [low]
- [x] T1.4 Expose `tokens(platforms)` and `labels(platforms)` as the module's public entrypoints (label = the existing `I18n.t(...platform_label.#{token})` join). complexity: [low]
- [x] T1.5 Update the label key from `pito.game.detail.platform_label` to a shared `pito.game.platform_label` in `config/locales/pito/game/en.yml`; set `switch: Switch` (was "Nintendo Switch"). complexity: [low]
- [x] T1.6 Replace `DetailComponent#platform_tokens`/`#platforms_label` with thin calls to `Pito::Game::PlatformTokens` (pass `@game.platforms`); the template keeps calling `platforms_label`. complexity: [low]
- [x] T1.7 Change the `:platform` column `value:` proc in `app/services/pito/message_builder/game/list_columns.rb` to `->(g) { Pito::Game::PlatformTokens.labels(g.platforms).to_s }`. complexity: [low]
- [x] T1.8 Change the `:platform` `SORT_SPECS` key in the same file to sort on `PlatformTokens.labels(g).to_s` so sort matches display. complexity: [low]
- [x] T1.9 Create `spec/services/pito/game/platform_tokens_spec.rb`: assert each bucket (PS5/PS4/"PlayStation 3"→ps; "Nintendo Switch 2"/"Switch Gen 1"→switch; Steam/"PC (Microsoft Windows)"/GOG/Epic/Amazon/Battle.net→steam), Xbox*/Google Stadia/Mac dropped, and de-dup (PS4+PS5 → one PlayStation). complexity: [low]
- [x] T1.10 Add a `list_columns` spec example asserting the platform cell renders normalized labels (no raw IGDB names). complexity: [low]
- [x] T1.11 Update the detail-component spec for the "Switch" label (was "Nintendo Switch") and the moved locale key. complexity: [low]
- [x] T1.12 Run `bundle exec rspec` for the touched specs; `bin/rubocop` clean. complexity: [low]
- [x] T1.13 Commit: "Normalize game platforms to PlayStation/Switch/Steam in list + detail". complexity: [manual]

## Phase 2 — Release date via Pito::Formatter

- [x] T2.1 Create `app/services/pito/formatter/release_date.rb` — `Pito::Formatter::ReleaseDate.call(game)` returning the precision-aware label (full date → `I18n.l(date, format: :long)` = "June 09, 2026"; month/quarter/year fallbacks; "TBA"). complexity: [low]
- [x] T2.2 Move the body of `Game#release_label` into the formatter; make `release_label` delegate to `Pito::Formatter::ReleaseDate.call(self)`. complexity: [low]
- [x] T2.3 Change the `:release_date` column `value:` proc in `list_columns.rb` to `->(g) { Pito::Formatter::ReleaseDate.call(g).to_s }`. complexity: [low]
- [x] T2.4 Create `spec/services/pito/formatter/release_date_spec.rb` covering full date "June 09, 2026", month-year, quarter, year-only, and TBA. complexity: [low]
- [x] T2.5 Run `bundle exec rspec` for the touched specs (incl. existing `Game#release_label` spec); `bin/rubocop` clean. complexity: [low]
- [x] T2.6 Commit: "Route release date through Pito::Formatter::ReleaseDate". complexity: [manual]

## Phase 3 — Wrapping multi-column table grid

- [x] T3.1 Add `.pito-data-grid` to `app/assets/tailwind/application.css`: base `display:grid; column-gap:0.5rem; row-gap:0.25rem;` + per-count rules `.pito-data-grid[data-cols="N"]` (N=2..8) where the first two columns are `max-content` and the rest are `repeat(N-2, minmax(0,1fr))` equally-spaced wrap-capable tracks. complexity: [low]
- [x] T3.2 Delete `SystemComponent#table_grid_cols`; add `table_col_count(n)` returning `[n,2].max` for the `data-cols` attribute (no inline style). complexity: [low]
- [x] T3.3 In `system_component.html.erb` (line ~111) replace the grid `class`/`<%= table_grid_cols %>` with `class="pito-data-grid<%= body ? ' mt-2 border-t border-line-default pt-2' : '' %>" data-cols="<%= table_col_count(n_cols) %>"`. complexity: [low]
- [x] T3.4 Apply the same replacement at the second grid site (line ~146, html branch). complexity: [low]
- [x] T3.5 Confirm non-`#` cells have no `whitespace-nowrap` so values wrap; leave heading cells nowrap (single-word headings). complexity: [low]
- [x] T3.6 Update `spec/components/pito/event/system_component_spec.rb` expectations that asserted the old `grid-cols-[…]`/`--pito-cols` → assert `pito-data-grid` + `data-cols="N"` and N spans. complexity: [low]
- [x] T3.7 Add an 8-column example (`#`, Game + 6 with-cols) asserting one `pito-data-grid` container, `data-cols="8"`, and 8 heading spans (no vertical-stack regression). complexity: [low]
- [x] T3.8 Run `bundle exec rspec spec/components`; `bin/rubocop` clean. complexity: [low]
- [x] T3.9 Commit: "Render list/data tables with a wrapping data-cols grid". complexity: [manual]

## Phase 4 — list games autocomplete: with connector + field tokens

(No noun-vocab reorder — bare `list ` "channels" default is intentional and untouched.)

- [x] T4.1 Extend `Pito::Suggestions::ListClauseGhost.ghost`: when registry present and no `with`/`sorted by` clause, add a connector branch that ghosts `with` after a completed noun (require noun + `\s+`; partial = last token; non-connector partials → no ghost). complexity: [high]
- [x] T4.2 In `suggestions_controller.js` `_computeLocalGhost`, after the chat-spec gate, `return null` when `chatSpec.name === "list"` so the client always defers the `list` verb to `POST /suggestions`. complexity: [low]
- [x] T4.3 Verify `_fetchDynamicGhost` applies `data.ghost.complete_current` (it does, line ~944) — no client ghost-apply change needed. complexity: [low]
- [x] T4.4 Add `list_clause_ghost_spec.rb` examples: `list games ` → ghost "with"; `list games w` → "ith"; `list games with ` → "platform"; `list games with d` → "eveloper"; `list games rpg` (filter partial) → no connector ghost. complexity: [low]
- [x] T4.5 Add `engine_spec.rb` example: `free_completions("list games ")` returns ghost "with" (server is the source of truth); confirm bare `list ` still ghosts "channels" (unchanged). complexity: [low]
- [x] T4.6 Add vitest cases to `spec/javascript/suggestions_controller.test.js`: typing `list games with ` defers to fetch and renders the mocked server ghost "platform"; `list games ` renders mocked "with"; assert the client does not locally resolve the `list` noun slot (defers instead). complexity: [high]
- [x] T4.7 Run `bundle exec rspec` (suggestions specs) and `npm test` (vitest); `bin/rubocop` clean; `node --check app/javascript/controllers/pito/suggestions_controller.js`. complexity: [low]
- [x] T4.8 Commit: "Drive list-games autocomplete from the server: with connector + field tokens". complexity: [manual]

## Phase 5 — Help message rewrite + `list games --help`

North star: the standard `help` message is a Standard (system) message with ONE
group for now — **GAMES** (yellow title) — containing a single kv-table row
`list games` → `use --help for more info`. And `list games --help` returns a
Standard message explaining the optional `with` columns and their aliases. **All
user-facing text comes from `Pito::Copy`** (`config/locales/pito/copy/en.yml` under
`pito.copy.*`). No inline style.

- [ ] T5.1 Inspect `Pito::MessageBuilder::Help::FollowUpActions`, `Pito::Chat::Handlers::Help`, the `sections`/yellow rendering in `system_component.html.erb`, and the `Pito::Copy.render` API + copy-key layout. complexity: [low]
- [ ] T5.2 Add `Pito::Copy` keys for the help message under `pito.copy.help.*` (e.g. `games_group_title` → "GAMES", `list_games_label` → "list games", `list_games_hint` → "use --help for more info"). complexity: [low]
- [ ] T5.3 Rewrite `Pito::Chat::Handlers::Help#call` to build a Standard system payload with one visible **GAMES** group (yellow title) and a single kv-table row (`list games` → `use --help for more info`), all text via `Pito::Copy`. complexity: [high]
- [ ] T5.4 Detect `--help` on the `list` verb: in `Pito::Chat::Handlers::List#call`, when `message.raw` matches `--help` (after a games noun), short-circuit to a help payload instead of listing. complexity: [low]
- [ ] T5.5 Add `Pito::Copy` keys (`pito.copy.list.games_help.*`) describing each optional `with` column + aliases (platform|platforms, genre|genres, developer|dev, publisher, release date, year); build a Standard message (kv-table: column ↔ aliases/description). complexity: [high]
- [ ] T5.6 Specs: help handler renders a GAMES group + the `list games` row; `list games --help` returns the columns explanation (asserts each of the 6 columns appears); `list games` (no flag) still lists normally. complexity: [low]
- [ ] T5.7 Run `bundle exec rspec` for the touched specs; `bin/rubocop` clean. complexity: [low]
- [ ] T5.8 Commit: "Rewrite help message (GAMES group) + add list games --help columns guide". complexity: [manual]

## Verification (end-to-end)

- `bundle exec rspec` green; `bin/rubocop` clean; `npm test` (vitest) green; `node --check` on the touched JS.
- Manual (via `/run` or dev server): in the shell type —
  - `list games` → clean 2-col table.
  - `list games with developer, publisher, genres, release date, year, platforms` → single wrapping table (not a vertical stack); Release reads "June 09, 2026"; Platform reads "PlayStation, Switch, Steam" with no Xbox/Google/Mac/PC.
  - Type `list games ` → ghost " with"; `list games with ` → ghost "platform"; cycle remaining field tokens; confirm "channels" never appears as a `with` field. (Bare `list ` still ghosts "channels" — intentional, unchanged.)
