# pito-astro — project-specific extensions

Project-scoped overrides for the Astro / static-site agent in pito.
Base template: `~/Dev/claude-dotfiles/agents/astro.md`.

## Pito specifics

- Target: `extras/website/` — Cloudflare Pages landing page.
- Stack: TBD. Currently a placeholder. Likely static HTML or Astro;
  decision queued for a later phase.
- Domain target: `pitomd.com` (production).

## File scope

`extras/website/` only. Never touch `app/`, `docs/`, `extras/cli/`,
`.claude-config/`.

## Out of scope

- Committing or pushing.
- Anything outside the website surface.
