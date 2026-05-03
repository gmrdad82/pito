# Manual test playbook — Monolith migration + unified `pito` CLI

**Repo:** `pito` (monolith) at `~/Dev/pito-project/pito` **Specs:**

- `docs/plans/beta/04-project-workspace/specs/monolith-migration.md`
- `docs/plans/beta/04-project-workspace/specs/project-workspace.md`

**Reviewer run:** 2026-05-03 (dated 2026-05-04 to align with the locked
amendment date).

## Pipeline summary

| Gate                           | Status      | Notes                                                                                      |
| ------------------------------ | ----------- | ------------------------------------------------------------------------------------------ |
| 1a cargo build --workspace     | PASS        | Already cached; clean build.                                                               |
| 1b cargo test --workspace      | PASS        | 103 passed, 0 failed, 0 ignored.                                                           |
| 1c cargo clippy -- -D warnings | **FAIL**    | 19 errors in pre-existing TUI code (Rust 1.95 stricter lints). See Blockers.               |
| 2 `pito` binary smoke          | PASS        | `version`, `--version`, `help`, `--help`, `footage` all behave correctly.                  |
| 3 RSpec (~slow excluded)       | PASS        | 684 examples, 0 failures.                                                                  |
| 4 prettier --check `**/*.md`   | **FAIL**    | 26 markdown files need a `prettier --write` pass. See Blockers.                            |
| 5 ci.yml YAML syntax           | PASS        | Parses cleanly.                                                                            |
| 6 Structural verification      | PASS        | 9 agents, `extras/cli/`, `extras/website/`, no `extras/terminal` or `extras/footage-sync`. |
| 7 Stale-reference grep         | **PARTIAL** | Spec hits are inside amendment notes (acceptable). Live-state docs have stragglers.        |

## Blockers (resolve before user validates)

1. **Clippy errors — 19 in `extras/cli/` source.** Rust 1.95 introduced stricter
   `collapsible_if`, `collapsible_match`, `manual_is_multiple_of`,
   `manual_clamp`, `branches_sharing_code`, and `single_match` lints. The
   migrated TUI code (largest hit: `extras/cli/src/app.rs`) trips them.
   `.github/workflows/ci.yml` runs `cargo clippy --all-targets -- -D warnings`
   on the `cli` job, so the first PR after this consolidation will fail CI.
   Files affected: `extras/cli/src/app.rs`, `extras/cli/src/keys.rs`,
   `extras/cli/src/commands/tui.rs`, `extras/cli/src/api/client.rs`,
   `extras/cli/src/ui/dashboard.rs`, `extras/cli/src/ui/videos.rs`. None of
   these were introduced by this consolidation — they are pre-existing in the
   migrated `pito-terminal` code, exposed by toolchain bump. **Fix path:**
   dispatch `cli-impl` to apply the auto-suggestable rewrites
   (`cargo clippy --fix --workspace --allow-dirty` is a starting point), then
   re-run `cargo clippy --workspace -- -D warnings` to confirm green.

2. **Prettier — 26 markdown files unwrapped or mis-wrapped.** The CI `docs` job
   runs `prettier --check '**/*.md'` and will fail. Affected files include all 9
   agent definitions, root `CLAUDE.md`, both Phase 4 specs,
   `docs/orchestration/agents.md`, `docs/orchestration/follow-ups.md`,
   `docs/orchestration/lanes.md`, `docs/orchestration/ux-defaults.md`,
   `docs/plans/beta/beta.md`, several phase plans, `extras/cli/README.md`,
   `extras/website/CLAUDE.md`. **Fix path:** dispatch `docs-keeper` (or run
   directly under architect supervision)
   `npx --yes prettier@latest --write '**/*.md'` then `git diff` to confirm only
   whitespace / wrapping changed.

## Concerns and suggestions (non-blocking)

1. **Stale "eight agents" narrative.** `.claude-config/README.md` still
   describes the old four-repo world: it lists `pito-rails`, `pito-mcp`,
   `pito-sh-impl` (renamed), references `pito-dev-kb`, and says "the eight Pito
   agents" (now nine). Should be rewritten to describe the monolith layout.
   Owner: `docs-keeper`.

2. **Stale repo-scope language in `docs/orchestration/agents.md`.** Lines 42
   (`pito-dev-kb`), 257 (`pito` and `pito-dev-kb`), 288–293 (still says
   `~/Dev/pito-project/`). The path is correct on disk during
   migration but the post-pivot canonical path is `~/Dev/pito/`, and the "Repo
   scope" sections should be path-scope sections under the monolith. Owner:
   `docs-keeper`.

3. **`extras/website/README.md` title is `# pito-website`.** Cosmetic — most
   other website surfaces now say "Pito website" or "extras/website". Owner:
   `docs-keeper` or `website-impl`.

4. **CI `cli` job working-directory.** `.github/workflows/ci.yml` sets
   `working-directory: extras/cli` for the `cli` job. That's fine for
   `cargo build/test/clippy/audit`, but it means `cargo build --workspace` from
   the repo root in CI is never exercised. Consider running clippy from the root
   too so workspace-wide changes are covered.

5. **`Cargo.lock` files in two places.** The repo root has `Cargo.lock`
   (workspace-level, the canonical one) and `extras/cli/Cargo.lock` also exists.
   With a workspace, the inner lockfile is usually redundant and can confuse
   `cargo`. Verify only the root `Cargo.lock` is committed and the inner one is
   a build artifact. (Both files differ in size: 53 KB at root, 47 KB inside
   cli.)

6. **`bin/dev` and `Procfile.dev` paths.** The migration spec says these should
   read from `extras/cli/target/release/pito`. This was not exercised in the
   gate run; verify during the manual smoke test below that `bin/dev` still
   starts cleanly.

7. **Frozen historical references.** Many alpha plans and old phase folders
   (`04-terminal-app`, `06-landing-page`, `01-dev-kb-setup`, etc.) still carry
   `pito-sh` / `pito-website` / `pito-dev-kb` strings. Acceptable — they are
   frozen records of past work — but worth a one-time grep audit after this
   lands to make sure no live-state file slipped in.

## Manual test steps

### Pre-merge sanity (before destructive steps)

These confirm the working tree is in the state this review captured.

1. **Action:** `cd ~/Dev/pito-project/pito && git status --short`
   **Expected:** A short list with `M .github/workflows/ci.yml`, `M .gitignore`,
   `M CLAUDE.md`, plus untracked `?? .claude-config/`, `?? Cargo.lock`,
   `?? Cargo.toml`, `?? docs/conversations/`, `?? docs/decisions/`,
   `?? docs/orchestration/`, `?? docs/plans/`, `?? extras/`. No other
   modifications.

2. **Action:** `ls extras/` **Expected:** Exactly two entries — `cli/` and
   `website/`. No `terminal/` or `footage-sync/`.

3. **Action:** `ls .claude-config/agents/ | wc -l` **Expected:** `9`.

### Destructive steps the user takes manually

These are the steps the architect cannot perform on the user's behalf.

1. Drop `~/Dev/pito-project/pito-dev-kb/.git`,
   `~/Dev/pito-project/pito-sh/.git`, `~/Dev/pito-project/pito-website/.git`,
   and the workspace shell's `~/Dev/pito-project/.git` if present. Verify with
   `find ~/Dev/pito-project -maxdepth 3 -name .git`.
2. Delete the now-orphaned source directories: `~/Dev/pito-project/pito-dev-kb`,
   `~/Dev/pito-project/pito-sh`, `~/Dev/pito-project/pito-website`.
3. Rename `~/Dev/pito-project/pito` to `~/Dev/pito` (or move the surviving
   monolith out of the wrapper). The architect's open shells will need a fresh
   `cd`.
4. From the new `~/Dev/pito` root, confirm `git remote -v` still points at the
   canonical `pito` remote.

### Post-rename verification

5. **Action:** `cd ~/Dev/pito && cargo build --workspace` **Expected:** Builds
   cleanly. Target dir is now `~/Dev/pito/target/`.

6. **Action:** `cargo test --workspace` **Expected:**
   `103 passed; 0 failed; 0 ignored`.

7. **Action (after blockers fixed):** `cargo clippy --workspace -- -D warnings`
   **Expected:** No warnings, no errors.

8. **Action (after blockers fixed):**
   `npx --yes prettier@latest --check '**/*.md'` **Expected:**
   `All matched files use Prettier code style!`

### `pito` CLI smoke test

9. **Action:** `./target/debug/pito version` **Expected:** `pito 0.1.0`.

10. **Action:** `./target/debug/pito --version` **Expected:** `pito 0.1.0`.

11. **Action:** `./target/debug/pito help` **Expected:** Help text listing
    `footage`, `help`, `version` subcommands and `-h`, `-V` flags. "Pito CLI"
    header.

12. **Action:** `./target/debug/pito --help` **Expected:** Identical to `help`.

13. **Action:** `./target/debug/pito footage` **Expected:**
    ``\`pito footage\` will be wired up in Phase 4 — see docs/plans/beta/04-project-workspace/specs/project-workspace.md.``

14. **Action:** Interactive — `./target/debug/pito` (no args). Run in a real
    terminal (not piped). **Expected:** Existing TUI launches into the channel
    browse / dashboard flow that the pre-migration `pito-sh` binary already
    shipped. `q` exits cleanly. No layout regressions vs. last `pito-sh` build.

### Rails web smoke test

15. **Action:** `bin/dev` **Expected:** Docker (Postgres + Redis) comes up; Puma
    starts on `:3000`; Sidekiq attaches; Tailwind watcher runs. No errors
    mentioning `pito-sh`, `pito-terminal`, or `extras/terminal`.

16. **Action:** Open `https://app.pitomd.com/` (or `http://localhost:3000`).
    **Expected:** Dashboard loads. Channel index loads. No 500s.

17. **Action:** Open `https://app.pitomd.com/dashboard` (or `/dashboard` on
    localhost). **Expected:** Charts render — channels per day, videos per day,
    etc. Bracketed-link legend toggles work.

18. **Action:** Open `/sidekiq` with the basic-auth credentials from
    `Rails.application.credentials`. **Expected:** Sidekiq web UI loads.

### MCP smoke test

19. **Action:** Trigger `list_channels` from the connected Claude.ai instance.
    **Expected:** Returns the live tenant's channels as JSON. No transport /
    auth errors.

20. **Action:** Trigger `delete_records` with `confirm: "no"` against a
    throwaway record id. **Expected:** Returns the confirmation prompt; does NOT
    delete. Then re-run with `confirm: "yes"` and verify deletion.

## Cleanup / rollback recipe

If something breaks after the destructive manual steps:

1. **Recoverable from GitHub:**
   - The `pito` repo's `.git` is preserved; if the working tree is corrupted,
     `git reset --hard origin/main` (with the user's explicit go-ahead) will
     restore the last pushed state. Note: the migration changes are NOT yet
     committed — local-only.
   - The `pito-sh` and `pito-website` GitHub remotes are intact (they live in
     their own repos on GitHub even though their local `.git` directories were
     dropped). Re-clone them if needed:
     `git clone git@github.com:<org>/pito-sh.git`,
     `git clone git@github.com:<org>/pito-website.git`.
2. **Local-only and unrecoverable:**
   - `pito-dev-kb` history (this repo) is local-only if not pushed. Confirm with
     `git log origin/main..HEAD` BEFORE dropping `.git`. The user has stated
     `pito-dev-kb` history is already on a remote — verify.
   - The workspace shell `pito-project/.git` is local-only and has minimal
     history (CLAUDE.md, .gitignore). Loss is acceptable per the migration spec.
3. **Re-derive monolith if needed.** If the rename or copy went wrong, check out
   a fresh clone of `pito` to a new directory and re-run the consolidation
   commits in order. The architect has the script.

## Sign-off checklist

Before the architect commits the consolidation:

- [ ] Blocker 1 (clippy) resolved. `cargo clippy --workspace -- -D warnings`
      green from `~/Dev/pito/`.
- [ ] Blocker 2 (prettier) resolved. `prettier --check '**/*.md'` green.
- [ ] Concerns 1, 2, 3 (stale doc references) addressed by `docs-keeper`.
- [ ] User has run steps 1–20 above and confirmed each expected outcome.
- [ ] User has explicitly authorized the commit.
