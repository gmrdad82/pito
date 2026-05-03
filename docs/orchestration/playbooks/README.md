# Manual Test Playbooks

This folder holds manual test playbooks produced by the **reviewer** agent
before user validation.

The reviewer runs the standard review pipeline against an implementation branch
and, when the diff is ready for human eyes, writes a playbook here describing
exactly what the user should click, type, and observe in order to validate the
change. The user works through the playbook on their machine and either approves
the merge or sends feedback back to the architect for another iteration.

## Naming

One file per merge, named:

```
<YYYY-MM-DD>-<feature-slug>.md
```

Example: `2026-05-01-video-workflow.md`.

The date is the date the playbook was written (the day of the planned merge),
not the date of the spec. The slug matches the feature slug used in the spec and
the implementation branch.

## Contents

A playbook should include:

- **Branch under test** — repo, worktree, branch name.
- **Prerequisites** — env vars, fixtures, accounts needed.
- **Setup steps** — how to boot the app(s) involved.
- **Walk-through** — numbered steps with the expected UI state, JSON payload, or
  terminal output at each step.
- **Lane 2 coverage** — separate sections for the Rails app, `pito-sh`, and the
  MCP surface where applicable. Skipped lanes are called out.
- **Rollback** — how to undo the change if validation fails.

Playbooks are kept after the merge as a record of what was tested, so future
audits can reconstruct the validation surface.
