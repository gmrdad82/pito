# pito-astro — project-specific extensions

Project-scoped overrides for the Astro / static-site agent in pito. Base
template: `~/Dev/claude-dotfiles/agents/astro.md`.

## What pito-astro owns

`extras/website/` — the Astro landing site for `pitomd.com`. Static-only output
(`output: "static"`), zero JS by default, deployed to Cloudflare Pages via the
`deploy-website` GitHub Actions workflow.

## Stack — locked

- **Framework:** Astro (latest stable, currently 6.x)
- **Output:** static, no SSR, no server runtime
- **Components:** `.astro` files; opt-in islands (React/Vue/Svelte) only when
  interactivity demands it
- **Styling:** plain CSS, no Tailwind on the website (pito's Rails app uses
  Tailwind; the marketing site duplicates the design tokens as plain CSS custom
  properties — see `src/styles/global.css`)
- **Design parity:** every CSS token mirrors the Rails app's
  `app/assets/tailwind/application.css` exactly (font stack, colors, dark theme
  tokens, sizing). When the Rails app's tokens change, the website's tokens must
  follow.

## Layout

- `src/layouts/Base.astro` — head + header + footer chrome, theme scripts
- `src/pages/index.astro` — under-construction placeholder; future Theta-phase
  work adds more pages here
- `src/styles/global.css` — design tokens + base styles
- `public/Pito.png`, `public/favicon.ico`, `public/manifest.json`,
  `public/robots.txt` — static assets, served verbatim

## Local dev

- Port: **3029** (pito's `30xx` convention — sits beside web 3027 and MCP 3028).
  Configured in `astro.config.mjs` `server.port`.
- Hostname: `local.pitomd.com` via the existing Cloudflare tunnel
  (`~/.cloudflared/config.yml` ingress rule routes `local.pitomd.com` →
  `127.0.0.1:3029`). Hot-reload works through the tunnel because Cloudflare
  proxies WebSockets.
- Direct fallback: `http://localhost:3029`.
- `bin/dev` (foreman via `Procfile.dev`) starts the Astro dev server in the
  `website` lane via `mise exec node@22 -- npm run dev`.

## Deploy

Two paths:

1. **CI (preferred)** — push to `main` with changes under `extras/website/**`
   triggers `.github/workflows/deploy-website.yml`, which builds + deploys via
   `cloudflare/wrangler-action@v3`.
2. **Manual fallback** — from `extras/website/`:
   ```
   npm install --ignore-scripts
   npm run build
   CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... \
     node node_modules/wrangler/bin/wrangler.js \
     pages deploy dist --project-name pito-website --branch main \
     --commit-dirty=true
   ```
   `--ignore-scripts` skips the `sharp` postinstall which fails on Node 22
   without prebuilt binaries — the parts of wrangler we use don't need sharp.

Cloudflare Pages project: `pito-website`. Custom domain attached: `pitomd.com`
(apex flatten via Cloudflare's proxied CNAME).

## CI lint + audit

`.github/workflows/website-ci.yml` runs on every push and PR that touches
`extras/website/**`:

- `npm ci` — clean install from lockfile
- `npm audit --audit-level=high` — fail on high+critical advisories
- `npx astro check` — TypeScript + Astro template typing
- `npm run build` — verify the build succeeds and `dist/` is produced

Dependabot updates npm deps weekly via `.github/dependabot.yml`.

## Hard rules (pito-specific overrides)

- **Casing:** lowercase by default (pito convention). Brand exceptions:
  `YouTube`, `OAuth`, `Git`, `Meilisearch`, `Voyage.ai`. `Pito` itself is always
  rendered as `pito` lowercase.
- **No JavaScript** beyond the inline theme-toggle script in `Base.astro`. If a
  page needs interactivity, prefer CSS-only solutions; only use Astro islands as
  a last resort.
- **Bracketed-link convention:** `[label]` for clickable elements (no inner
  padding spaces), matching the Rails app's 2026-05-10 tightening. Examples:
  `[home]`, `[connect]`, `[add]`. Drop redundant nouns when surrounding context
  supplies them. The `[ ]` / `[x]` checkbox indicator is a separate convention
  and keeps its inner space. Canonical: `docs/design.md` → "Bracketed Links /
  Buttons" and "Bracketed labels: minimum text".
- **No red on decorative elements.** `--color-danger` is in the token set but is
  reserved for failure states only, never for emphasis or branding.
- **No analytics, no tracking, no third-party JS.** Marketing site stays
  surveillance-free.

## Astro 101 — for someone new to it

- **`.astro` files** are like JSX/HTML hybrids. The top section (between `---`
  markers) is a Node-style script that runs at BUILD time only — not in the
  browser. Below the second `---` is HTML markup with template-literal-style
  interpolation (`{variable}`).
- **Static by default.** Astro generates plain HTML files; no JS ships unless
  you explicitly add `<script>` tags or `client:load`-marked components.
- **Islands.** When you need interactivity, you import a component
  (React/Vue/Svelte) and add `client:load` / `client:idle` / `client:visible`.
  The island ships its own JS bundle, hydrates in isolation. pito doesn't use
  islands yet; static HTML is enough.
- **Routing.** File-based — `src/pages/index.astro` is `/`,
  `src/pages/about.astro` is `/about`. Dynamic routes use bracket syntax:
  `src/pages/[slug].astro`.
- **Build output.** `npm run build` writes to `dist/`. Pure HTML + CSS +
  (optional) JS bundles. Deploy that directory to any static host. Cloudflare
  Pages takes the `dist/` directly.
- **Layouts.** Reusable shells for pages — `src/layouts/Base.astro` is one. A
  page imports the layout and slots its content via `<slot />`.
- **CSS.** Per-component scoped CSS by default (Astro generates unique class
  names). Global CSS goes in `src/styles/`. The pito site uses global CSS only
  because the design tokens are intentionally global.
- **Dev server.** `npm run dev` boots a hot-reloading server. Edits to `.astro`
  files reflect instantly in the browser.

## File scope

`extras/website/` only. Never touch `app/`, `docs/` (except this very file when
updating extensions), `extras/cli/`, `.claude-config/`, `config/`, the Rails
app, the Rust crate, GitHub workflow files outside `deploy-website.yml` and
`website-ci.yml`.

## Out of scope

- Committing or pushing — master agent does that after user validates.
- Cloudflare API calls (deploy is via wrangler in CI).
- DNS / domain configuration (handled by master agent or operator).
- Anything that requires running a server in production (this is static).
