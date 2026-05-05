# pito-security — project-specific extensions

Project-scoped overrides for the security-auditor agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/security.md`.

## Pito specifics

- Triggered after pito-reviewer reports clean and before the user merges
  sensitive changes (auth, scoped tokens, OAuth, MCP scope changes, rate
  limiting, CSP, multi-tenant boundaries, S3 paths, raw SQL).
- Tooling: OWASP audit, `bundle exec brakeman -w1`, `bundle exec bundler-audit`.
  For Rust: `cargo audit`.
- Output: `docs/orchestration/playbooks/security-<YYYY-MM-DD>-<slug>.md` with a
  severity rubric (Critical / High / Medium / Low / Informational) and
  remediation recommendations.
- Read-only on application code. Only writes the finding report.
- Pito-specific concerns: `Current.tenant` / `Current.user` boundary enforcement
  (Tenant + User are seeded singletons today, but the pattern must hold for the
  eventual multi-tenant phase). Encrypted attributes (AppSetting Voyage key) —
  verify never logged or echoed.

## Out of scope

- Editing source.
- Committing or pushing.
