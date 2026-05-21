# Website — Astro / pitomd.com

> Skeleton — to fill in fresh after the doc walk.

## Layout

(placeholder — `extras/website/`. Astro 4. Static SSG. Zero-JS by default.
React/Vue/Svelte islands only when needed.)

## Build

(placeholder — `cd extras/website && pnpm install && pnpm build`. Output
to `extras/website/dist/`.)

## Deploy

(placeholder — Cloudflare Pages via wrangler. Credentials via
`Rails.application.credentials.cloudflare` (`api_token` + `client_id`).
`pito-astro` agent owns the deploy flow. Build-then-deploy invariant.
CI fallback at `.github/workflows/deploy-website.yml`.)

## Domains

(placeholder — `pitomd.com` apex (production). `*.pages.dev` for branch
previews.)

## Content

(placeholder — landing page only at the moment. Sections: hero, about,
contact, footer with version + commit SHA + apex domain.)

## Style

(placeholder — same Dracula palette + system mono as the Rails app. 13px
base + line-height 1. No font assets bundled (system mono only).)

## Local preview

(placeholder — `pnpm dev` runs at http://localhost:4321.)
