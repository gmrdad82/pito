# Extending PITO

PITO is a one-person tool, but it's built to be extended — by me later, or by
anyone who forks it. This is the map for the four most common "I want to add a…"
tasks: a **theme**, a **language**, a new kind of **message content**, and a new
reveal **fx**. It's dual-audience on purpose — written to read clearly for a human
on GitHub _and_ to be precise enough for an AI agent working in the tree.

Read [`architecture.md`](architecture.md) (dispatch flow + data model) and
[`design.md`](design.md) (the visual contract) first — the guides below lean on
them and won't re-explain the invariants.

A few rules thread through everything here:

- **User-facing strings go through `Pito::Copy.render`** (the `pito.copy.*`
  1-or-50 dictionary: a key resolves to exactly one string _or_ ≥50 variants).
  Never call `I18n.t` on a copy key.
- **Builders produce structured `jsonb`; the caller sets the event kind.** No
  rendered HTML in payloads beyond bodies that regenerate on every render.
- **`Pito::Stream::Broadcaster` is the only way onto the scrollback.** Never
  broadcast from a controller, model, or builder.
- **Some files are generated** (e.g. `app/assets/tailwind/themes.css`) — edit the
  source, run the rake task, never the artifact.

> File/line references rot. Where a guide cites a constant (`AppSetting::SOUND_ENABLED_KEY`)
> or a path, trust the symbol over any line number — grep for it.

## Contents

- [Adding a new theme](#adding-a-new-theme)
- [Adding a new language](#adding-a-new-language)
- [Adding a new message content type](#adding-a-new-message-content-type)
- [Adding a new fx](#adding-a-new-fx)

---

## Adding a new theme

PITO's palette is data-driven: `app/assets/tailwind/themes.css` is a **generated
file** (`rake pito:themes:export`). The one invariant: never hand-edit
`themes.css`. All theme work happens in the source layer; the generator writes the
file.

### Steps

1. **Create a definition file** in `app/services/pito/themes/definitions/`. Name it
   `<slug_underscored>.rb` (e.g. `rose_pine.rb` for slug `"rose-pine"`). The
   registry auto-discovers every `*.rb` file in that directory on first access — no
   other wiring needed.

2. **Write the definition.** All `base:` keys are mandatory; `overrides:` is
   optional:

   ```ruby
   require_relative "../registry"

   Pito::Themes::Registry.register(
     slug:  "rose-pine",        # kebab-case; the data-theme="…" value
     label: "Rosé Pine",        # display label in the /themes picker
     mode:  :dark,              # :dark or :light — which group it shows in
     base: {
       bg:     "#191724",       # → --bg-root
       fg:     "#e0def4",       # → --fg-default
       purple: "#c4a7e7",       # → --accent-purple
       blue:   "#9ccfd8",       # → --accent-blue
       cyan:   "#ebbcba",       # → --accent-cyan
       green:  "#31748f",       # → --accent-green
       yellow: "#f6c177",       # → --accent-yellow
       orange: "#ea9a97",       # → --accent-orange
       red:    "#eb6f92",       # → --accent-red
     },
     overrides: {               # optional; pin any derived token
       surface:  "#1f1d2e",     # → --bg-surface
       elevated: "#26233a",     # → --bg-elevated
     }
   )
   ```

   **Token derivation.** Six tokens auto-derive from `bg`/`fg` by linear RGB mix
   unless overridden: `bg_surface = mix(bg,fg,.06)`, `bg_elevated = mix(.12)`,
   `border_default = mix(.16)`, `border_faded = mix(.28)`, `fg_dim = mix(fg,bg,.40)`,
   `fg_faded = mix(.60)`. If the derived values fight your palette (unusual contrast,
   coloured mid-tones), pin them in `overrides:` — both short (`surface:`,
   `fg_dim:`) and full (`bg_surface:`) key forms work. `--brand-pito` (`#5170ff`) is
   a constant the generator always emits unchanged.

3. **Regenerate the CSS:**

   ```bash
   bin/rails pito:themes:export
   ```

   It overwrites `app/assets/tailwind/themes.css`. Confirm a
   `[data-theme="rose-pine"] { … }` block appears.

4. **The picker is automatic.** `Pito::Themes::Registry.grouped` drives the themes
   sidebar; your `mode:` decides Dark vs Light. `PATCH /settings/theme` validates
   slugs against the registry, so the theme is immediately selectable and persists
   to `AppSetting.theme`.

5. **Update `README.md` manually.** The `## Themes` section's count ("19 built-in
   themes"), the dark/light slug lists, and the gallery table are NOT generated.
   Bump the count, add the slug, add a gallery row with a screenshot.

### Verify

```bash
bundle exec rspec spec/services/pito/themes/
```

`registry_completeness_spec.rb` checks the exact theme count (update the `eq(19)`
expectation), group sizes, that every theme resolves all 16 tokens to valid hex, and
that `brand_pito` is `#5170ff` everywhere.

### Gotchas

- **Never edit `themes.css` by hand** — the next export silently overwrites you.
- **`brand_pito` isn't yours to change** — the shimmer + `data-accent="pito"` bar are
  tuned to `#5170ff` across all themes.
- **The definition file is `load`-ed, not `require`-d**, so it can re-evaluate after a
  dev code reload — re-registering a slug replaces, never duplicates.
- **Light themes usually need explicit `overrides:`** — the derivation doesn't
  auto-invert, so `border_*` / `fg_dim` can come out too subtle on a light bg. Check
  the render.
- **The README count + lists are manual** — the most common way to ship a theme that
  works but makes the docs lie.

---

## Adding a new language

PITO ships English-only: every locale file under `config/locales/pito/` is a single
`en.yml`, and there's no locale switcher yet. A new language is two jobs — the YAML
files, and the mechanism that selects the locale.

**Invariant:** every `pito.copy.*` string goes through `Pito::Copy.render` /
`render_html`. Never `I18n.t` a copy key directly — those values may be arrays,
which `I18n.t` can't sample.

### Steps

1. **Create a parallel `<locale>.yml` for every `en.yml`** under
   `config/locales/pito/` (`auth/`, `chat/`, `confirmation/`, `copy/`, `event/`,
   `follow_up/`, `footage/`, `game/`, `grammar/`, `hashtag/`, `jobs/`, `not_found/`,
   `palette/`, `shell/`, `sidebar/`, `slash/` + `slash/help/` + `slash/theme/`,
   `start_screen/`, `video/`, `youtube_connections/`). Keep the root YAML key as the
   locale code (`es:`). Rails discovers `config/locales/**` recursively — no
   load-path change.

2. **Mirror the key tree exactly; translate only values.** Keys are code-facing
   identifiers and must be bit-for-bit identical to `en.yml`:

   ```yaml
   # config/locales/pito/start_screen/es.yml
   es:
     pito:
       start_screen:
         tip_prefix: "Consejo"
         repo_link: "Código fuente"
         license_link: "AGPL-3.0"
   ```

3. **Honour the 1-or-50 rule in `copy/es.yml`.** Each leaf under `pito.copy.*` is a
   single string or a variant pool of ≥50 (`Pito::Copy::Audit::STANDARD_MIN_SIZE`).
   Don't trim a 50-entry English pool to 12 Spanish lines — the audit flags anything
   below 50.

4. **Expose the locale** in `config/application.rb`:
   `config.i18n.available_locales = %i[en es]`.

5. **Wire a switcher** (none exists). Mirror the `AppSetting.timezone` pattern: add a
   `LOCALE_KEY` helper to `app/models/app_setting.rb`, a `before_action :set_locale`
   in `ApplicationController` that sets `I18n.locale` from `AppSetting.locale` when
   it's in `available_locales`, and a `/config locale <code>` command to persist it.

6. **Run the audit:** `bundle exec rake pito:copy:audit`. It walks `pito.copy.*` for
   the current `I18n.locale` — set `I18n.locale = :es` in a console and call
   `Pito::Copy::Audit.call` to audit the new locale.

### Worked example — Spanish (`es`)

Start small: `cp config/locales/pito/not_found/en.yml …/es.yml`, set the root to
`es:`, translate the one value. Then do `shell/` (UI labels), `slash/` (errors), and
`grammar/` (command descriptions) — the strings you read most. Leave `copy/es.yml`
for last: it's ~6.5k lines and every pool must reach 50.

### Verify

```bash
bundle exec rspec                  # green — no I18n::MissingTranslationData
bundle exec rake pito:copy:audit   # zero "BELOW STANDARD" entries
```

### Gotchas

- **Never rename keys** — code calls them; a renamed key raises
  `I18n::MissingTranslationData` (in prod it silently falls back to English via
  `config.i18n.fallbacks = true`, which hides the gap — audit before deploying).
- **Variant pools must hit 50** or the copy feels repetitive and the audit fails.
- **`Pito::Copy.render` is the only gate** — `I18n.t` on a multi-variant key returns
  the raw Array, doesn't sample, doesn't interpolate.
- **Preserve `%{placeholder}` tokens** — dropping one raises
  `Pito::Copy::MissingPlaceholder` at the first render.

---

## Adding a new message content type

A "new content type" is a new **payload shape** — a structured `jsonb` hash a
ViewComponent turns into DOM. Not a new event kind, not new cable wiring. The one
invariant: **builders return payload hashes; callers set the kind. A builder never
decides its own chrome.**

### Steps

1. **Add copy keys** in `config/locales/pito/copy/en.yml` under `pito.copy.*` (1 or
   ≥50 variants). Use `Pito::Copy.render` / `render_html`, never hardcoded text.

2. **Create a sub-ViewComponent** at
   `app/components/pito/<domain>/<verb>_component.rb` (+ `.html.erb`). For most
   content types you don't touch `SystemComponent` — it renders `html: true` payloads
   directly (instant, no reveal). Design rules (full contract in
   [`design.md`](design.md)): no arbitrary Tailwind from variables (JIT purges them);
   use `data-cols="N"` with the static `.pito-data-grid[data-cols="N"]` rules;
   `border-radius: 0`; no `style=`; no hover.

3. **Write the builder** at
   `app/services/pito/message_builder/<domain>/<verb>.rb` — a `module_function`
   module with a single `.call` returning a **Hash with string keys** (symbol keys
   stringify on `jsonb` persist; string keys round-trip cleanly):

   ```ruby
   module Pito
     module MessageBuilder
       module Stats
         module Chart
           extend Pito::MessageBuilder::Helpers
           module_function

           def call(game)
             intro = Pito::Copy.render_html(
               "pito.copy.stats.chart_intro", { title: game.title }, shimmer: [:title]
             )
             body = render_component(Pito::Stats::ChartComponent.new(game:, intro:))
             html_payload(body:, game_id: game.id)
           end
         end
       end
     end
   end
   ```

   `Pito::MessageBuilder::Helpers` gives you `render_component(component)` (renders a
   ViewComponent to an HTML string) and `html_payload(body:, **extra)` (returns
   `{ "body" => …, "html" => true }.merge(extra.stringify_keys)`). To make the
   message repliable, call
   `Pito::FollowUp.make_followupable!(payload, target: "<target>", conversation:)`
   before returning.

4. **Wire into a handler and choose the kind** — the handler picks the chrome:

   ```ruby
   events = [
     { kind: :system,   payload: Pito::MessageBuilder::Game::Detail.call(game, conversation:) },
     { kind: :enhanced, payload: Pito::MessageBuilder::Stats::Chart.call(game) },
   ]
   Pito::Chat::Result::Ok.new(events:)
   ```

   Kinds: `:system` (first/primary segment, surface bar), `:enhanced` (later
   segment, pito-blue bar), `:error` (red bar). `Dispatch::Finalizer` auto-promotes
   extra `:system` events to `:enhanced`, but be explicit. **Never call the
   Broadcaster from a handler** — return a `Result`; the Finalizer owns persistence +
   cable writes.

5. **A brand-new event kind is rare.** The existing kinds (`system`, `enhanced`,
   `error`, `confirmation`, `echo`, `thinking`, `theme_diff`, + `_follow_up`
   variants) cover almost everything. If you truly need new chrome: add the string to
   `Event::KINDS` (`app/models/event.rb`), create the component, and register it in
   `Pito::Stream::EventRenderer::COMPONENT_CLASSES`. That's a `[high]` task — plan it
   separately.

### Verify

```bash
bundle exec rspec \
  spec/services/pito/message_builder/stats/chart_spec.rb \
  spec/components/pito/stats/chart_component_spec.rb \
  spec/services/pito/chat/handlers/show_spec.rb
```

### Gotchas

- **Builders never choose the kind.**
- **Payload keys must be strings** — `html_payload` stringifies for you; if you build
  by hand, use `"body"` not `body:`.
- **Payloads persist and re-render later** — never embed a live timestamp or auth
  state in a raw payload field; render timestamps live (via
  `Pito::Event::TimestampPrefixComponent`) so a scrollback refresh shows the right
  time.
- **`Pito::Stream::Broadcaster` is the only broadcast path** — never
  `ActionCable.server.broadcast` from a controller/model/builder.
- **Text via `Pito::Copy` only**; run `rake pito:copy:audit`.
