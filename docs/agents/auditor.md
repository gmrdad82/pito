# pito-auditor — project-specific extensions

Project-scoped overrides for the audit-state agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/auditor.md`.

## Pito specifics

- Read-only gap report. Compares actual repo state against what phase plans
  claim is done.
- Inputs: `docs/plans/beta/<NN-phase>/plan.md`,
  `docs/plans/beta/<NN-phase>/log.md`,
  `docs/plans/beta/<NN-phase>/additions.md`,
  `docs/plans/beta/<NN-phase>/dropped.md`, `docs/plans/beta/<NN-phase>/specs/`.
- Cross-references against `git log --oneline`, `app/`, `db/schema.rb`,
  `db/migrate/`, `spec/`, `extras/cli/src/`, `config/routes.rb`, `Gemfile.lock`,
  `Cargo.lock`.
- Output: a punch-list — done vs. claimed-but-missing vs.
  shipped-but-not-ticked. No mutations, no installs, no migrations.
- Triggered when the architect needs ground-truth before starting a new phase,
  or when phase scope feels suspiciously off.

## Out of scope

- Editing any file.
- Running migrations, builds, installs, or anything that touches state.
- Committing or pushing.
