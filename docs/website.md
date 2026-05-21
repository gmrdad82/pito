# Website — Astro / pitomd.com

## Purpose

A simple static landing page at `pitomd.com`. Sole goals:

1. Something at the apex domain (so the domain isn't a 404).
2. Provide a favicon for Google's crawler / icon cache.

**Not** a marketing funnel. **Not** a docs site. **Not** a feature
showcase.

## Layout

`extras/website/`. Astro 4. Static SSG. Zero-JS by default. React / Vue
/ Svelte islands only when actually needed (currently: none).

## Style

- Same Dracula palette as the Rails app
- System monospace font (no bundled font files)
- 13px base + `line-height: 1`
- Minimal content: hero + about + contact + footer

## Build

```
cd extras/website
pnpm install
pnpm build       # outputs to dist/
pnpm dev         # local preview at http://localhost:4321
```

## Deploy

Cloudflare Pages via `wrangler`. Credentials live in
`Rails.application.credentials.cloudflare`:

- `api_token`
- `client_id` — maps to `CLOUDFLARE_ACCOUNT_ID` env var at deploy time

The **`pito-astro` agent** owns the deploy flow. The agent reads
credentials from Rails credentials via `bin/rails runner`, exports them
to shell env vars scoped to the deploy command's lifetime, and invokes
`wrangler`.

**Invariant: build then deploy.** Never deploy without rebuilding.

CI fallback at `.github/workflows/deploy-website.yml` runs the same
sequence when the master agent picks CI over local deploy (e.g., for an
audit-trail commit).

## Domains

- `pitomd.com` apex — production
- `*.pages.dev` — preview deployments (per branch / per commit)
