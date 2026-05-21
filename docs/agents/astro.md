# pito-astro — project-specific extensions

Project-scoped overrides for the Astro / static-site agent in pito. Base
template: `~/Dev/claude-dotfiles/agents/astro.md`. Read project-wide rules in
`~/Dev/pito/CLAUDE.md` first.

## What pito-astro owns

`extras/website/` — the Astro landing site for `pitomd.com`. Static-only output,
zero JS by default, deployed to Cloudflare Pages.

## Project overrides

- **Canonical reference:** `docs/website.md` is the source of truth for the
  marketing site (stack, layout, deploy flow, design parity). Read it first.
- **Design parity:** every CSS token mirrors the Rails app's design tokens
  exactly. When the Rails app's `docs/design.md` tokens change, the website's
  tokens follow.
- **No analytics, no third-party JS, no tracking.** Marketing site stays
  surveillance-free.

## Cloudflare credentials

Credentials live in `Rails.application.credentials.cloudflare`, NOT in env
files. Current keys:

```yaml
cloudflare:
  api_token: <token-with-Pages:Edit-scope>
  client_id: <cloudflare-account-id-equivalent>
```

The agent maps `client_id` → `CLOUDFLARE_ACCOUNT_ID` at deploy time. Source via
`bin/rails runner` into env vars scoped to the deploy command's lifetime; never
write to disk.

```bash
export CLOUDFLARE_API_TOKEN="$(cd ~/Dev/pito && bin/rails runner 'puts Rails.application.credentials.cloudflare.api_token')"
export CLOUDFLARE_ACCOUNT_ID="$(cd ~/Dev/pito && bin/rails runner 'puts Rails.application.credentials.cloudflare.client_id')"
```

## Deploy contract

Every successful local `npm run build` is followed by a `wrangler pages deploy`
to project `pito-website`. A build that is not deployed is not done. CI fallback
via `.github/workflows/deploy-website.yml` is the audit-trail path.

Smoke check after deploy:

```bash
curl -sI https://pitomd.com/ | head -3
```

Should return `HTTP/2 200`. Edge propagation takes 30-60s.

## Pointers

- `docs/website.md` — stack, layout, deploy, design parity (canonical).
- `docs/design.md` — visual tokens to mirror.
- `CLAUDE.md` → "Astro deployments" — deploy contract and credentials policy.

## File scope

`extras/website/` only. Never touch `app/`, `docs/` (except this file),
`extras/cli/`, `config/`, the Rails app, the Rust crate, or workflows outside
`deploy-website.yml` and `website-ci.yml`.

## Out of scope

- Committing or pushing.
- DNS / domain configuration.
