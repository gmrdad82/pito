# Phase 14 — Backup / Restore Tooling

> **Goal:** Build comprehensive backup and restore tooling for every piece of
> state Pito accumulates: Postgres (relational + pgvector), Meilisearch indices,
> Redis (jobs in flight), KB filesystems, encrypted credentials. Test the
> restore path end-to-end. By Phase 14, losing the laptop should be
> inconvenient, not catastrophic. Tooling built once, tested locally, ports
> unchanged to Hetzner in Phase 16.

**Depends on:** Phase 10 (pgvector data is now expensive to recompute — backups
protect the Voyage spend), Phase 11 (workflow features mean state matters more),
Phase 13 (observability surfaces backup status).

**Unblocks:** Phase 16 (Hetzner deployment with backup automation in place from
day one — production cutover happens with backups already running).

---

## Why Phase 14 is now

Each preceding phase added a new piece of state, and by Phase 14 the
accumulation is significant:

- Phase 1: KB markdown structure
- Phase 2: Postgres schema
- Phase 3: User accounts, ApiTokens, Tenant
- Phase 7: Encrypted Google OAuth tokens (irreplaceable — re-OAuthing requires
  user action and may fail)
- Phase 9: KB content (the user's actual production notes — irreplaceable)
- Phase 10: Embeddings (~$5 of Voyage compute; replaceable but expensive)
- Phase 11: Production state, video uploads in progress, workflow history
- Phase 12: User accounts, sessions, Doorkeeper applications

That's enough irreplaceable data that ad-hoc backups are no longer acceptable.
Phase 14 builds tooling once, tests it on the laptop, and the same tooling
deploys to Hetzner in Phase 16 with only path / cron differences.

The restore path is the actual test. **Backups that have never been restored are
not backups.** This phase mandates a full end-to-end restore drill before
completion.

---

## In scope

### Postgres backup

- `pg_dump --format=custom --compress=9 --no-acl --no-owner` of the database
- Custom format includes pgvector data (vectors are stored as standard column
  data; `pg_dump` handles them transparently)
- Stored in `~/Backups/pito/postgres/<ISO_timestamp>.dump`
- Daily automatic via systemd timer (laptop) or cron (Hetzner — Phase 16
  inherits the same script)
- Manual on-demand via CLI command
- **Retention policy: 30 daily / 8 weekly (Sundays) / 6 monthly (1st of month)**
  — capped at ~44 retained backups per type at steady state

### Meilisearch backup

- Use Meilisearch's `POST /snapshots` snapshot API
- Snapshots are written to Meili's data directory; a Pito script copies them
  into `~/Backups/pito/meilisearch/<ISO_timestamp>.snapshot`
- Same retention policy as Postgres
- Snapshot import on restore via Meili's `--import-snapshot` flag at startup

### Redis backup (low priority but tracked)

- Pito's Redis stores Sidekiq state (queued jobs, retry sets) — recreatable but
  inconvenient if lost
- Optional `BGSAVE` snapshot to RDB; copied to
  `~/Backups/pito/redis/<ISO_timestamp>.rdb`
- Documented as best-effort: in disaster recovery, expect to restore-as-empty
  Redis and accept that in-flight Sidekiq jobs are lost
- Keep retention shorter (7 daily) since the data is cheap to recreate

### KB filesystem backup

The KB roots (`pito-dev-kb`, `pito-website`, plus any project-notes roots
introduced by Phase 4 — Project Workspace) are git repositories. **Pushing them
to GitHub is the backup.** No file copy needed. The original spec also listed
`pito-yt-kb`; that repo has been dropped and channel-level notes will reuse the
project-notes pattern from Phase 4.

- CLI: `bin/pito backup:kb_status` checks each root: `git status` (working tree
  clean?), `git log` (ahead of remote?), prints status table
- Documentation explicitly states: "git push is your KB backup; this command
  confirms everything is committed and pushed"
- The script does **not** auto-commit or auto-push. The user manages git cadence
  manually (per `beta.md`'s working principles).

### Credentials backup

- Rails master key + `credentials.yml.enc` — encrypted at rest, but losing the
  master key means losing decryption ability for everything (OAuth tokens, API
  keys, etc.)
- This phase **cannot automate** master key handling. Instead it documents:
  - Where the master key lives (`config/master.key` or
    `config/credentials/<env>.key`)
  - Explicit secure storage path (1Password / Bitwarden / encrypted USB)
  - The restore runbook prompts the user: "Do you have your master key? Without
    it, the restored database is useless."

### Restore tooling

- `bin/pito restore:postgres <dumpfile>` — interactive: confirms target DB
  (typed phrase, not just "y"), drops and recreates target, runs `pg_restore`
- `bin/pito restore:meilisearch <snapshotfile>` — uses Meili's snapshot import
  via container restart with `--import-snapshot`
- `bin/pito restore:check` — runs after restore: verifies record counts
  non-zero, samples data sanity, KB symlinks intact, embedding columns populated
- Each restore action audits to `log/operational_audit.log` (since the restore
  obliterates Postgres-based audit data)

### Backup management CLI

- `bin/pito backup:postgres` — manual trigger; takes a fresh dump, runs
  `pg_restore --list` for integrity verification
- `bin/pito backup:meilisearch` — manual trigger
- `bin/pito backup:redis` — manual trigger; best-effort
- `bin/pito backup:kb_status` — KB git status check
- `bin/pito backup:all` — runs Postgres + Meili + Redis + KB status sequentially
- `bin/pito backup:list` — shows all backup files (path, size, age, retention
  bucket)
- `bin/pito backup:prune` — removes backups outside retention; `--dry-run` flag
  for safety; defaults to dry-run (typed phrase to actually delete)

### Off-site copy (optional in Beta, mandatory in Phase 16)

- Backups can optionally sync to an off-site S3-compatible store
- Configuration via env vars: `BACKUP_REMOTE_ENDPOINT`, `BACKUP_REMOTE_BUCKET`,
  `BACKUP_REMOTE_ACCESS_KEY`, `BACKUP_REMOTE_SECRET_KEY`, `BACKUP_REMOTE_PREFIX`
- Recommended providers: Hetzner Storage Box, Backblaze B2, Wasabi (cheap,
  S3-compatible)
- Off by default for laptop dev (the user's laptop is treated as the production
  stand-in but isn't shouldering production-grade DR yet)
- Phase 16 turns this on for production deployment
- Implementation: shell-out to `aws-cli` (with `--endpoint-url`) or `rclone`.
  Recommend `rclone` for simpler config across providers.

### Backup status in observability

- Phase 13's `/stats` page gets a "Backup Status" section showing:
  - Last successful backup time per type (Postgres, Meili, Redis, KB)
  - Total backup storage used locally
  - Off-site upload status (if configured)
  - Age warning if last backup > 36 hours
- Threshold default (from Phase 13's alert system): "warn if last backup > 36
  hours" — fires the visual banner

### The restore drill (mandatory)

End of phase: a full restore drill to a separate, parallel test environment.
This is **not optional**. Until the drill succeeds, the phase is not done.

**Drill procedure:**

1. Spin up a parallel test environment via Docker — separate Postgres container,
   separate Meili container, fresh data directories
2. Take a current backup of the laptop's "production-like" Pito
   (`bin/pito backup:all`)
3. Configure the test environment to use copies of the KB roots
4. Restore Postgres dump to test environment
5. Restore Meili snapshot to test environment
6. Run `bin/pito restore:check`
7. Start a parallel Pito instance against the restored data
8. Verify: dashboard renders, search works, related-content queries work
   (pgvector indices intact), KB integration works, all token-based auth still
   works (encryption keys intact)
9. Document drill outcome in `log.md`: timing, surprises, fixes needed

If the drill reveals issues, fix and redo. If the drill succeeds, the phase
passes.

### Out of scope

- Continuous replication / streaming WAL backups (overkill for single-user Beta)
- Point-in-time recovery (overkill)
- Encrypted backup at rest (Phase 16 concern for production; Beta uses laptop
  filesystem encryption)
- Cross-region replication (Theta scale concern)
- Automated restore testing on a schedule (manual drill at end of Phase 14 is
  sufficient; Phase 16 may add CI-style restore drills if budget allows)
- Application-level snapshot consistency (Pito doesn't have transactions
  spanning Postgres + Meili + filesystem; eventual consistency between stores is
  acceptable)

---

## Plan checklist

### Postgres backup

- [ ] `bin/pito backup:postgres` script (or Rake task)
- [ ] Reads `DATABASE_URL`, runs
      `pg_dump --format=custom --compress=9 --no-acl --no-owner`
- [ ] Writes timestamped file to `~/Backups/pito/postgres/`
- [ ] Verifies dump integrity via `pg_restore --list`
- [ ] Specs (with a test database) — backup runs, dump exists, dump is
      restorable
- [ ] systemd timer (laptop) or cron entry for daily 2 AM local time
- [ ] Document setup in `pito/docs/backup.md`

### Meilisearch backup

- [ ] `Backup::Meilisearch.snapshot!` service: calls Meili's `POST /snapshots`
      API; polls until complete; copies snapshot file to
      `~/Backups/pito/meilisearch/`
- [ ] CLI: `bin/pito backup:meilisearch`
- [ ] Specs against a test Meili instance
- [ ] Schedule: daily

### Redis backup

- [ ] CLI: `bin/pito backup:redis` — runs `redis-cli BGSAVE`; copies the
      resulting RDB
- [ ] Document best-effort nature in the runbook

### KB status check

- [ ] CLI: `bin/pito backup:kb_status` — for each configured KB root
      (`PITO_DEV_KB_PATH`, `PITO_WEBSITE_PATH`, plus any project-notes roots
      from Phase 4 — Project Workspace; `PITO_YT_KB_PATH` was retired with the
      `pito-yt-kb` repo):
  - Runs `git status --porcelain` (returns dirty if non-empty)
  - Runs `git log @{u}..HEAD` (returns ahead-count)
  - Prints status table with row per KB
- [ ] Document: "git push IS your backup for KB content"

### Restore tooling

- [ ] CLI: `bin/pito restore:postgres <file>` — interactive confirmation (typed
      phrase like "RESTORE-AND-DROP"), drops/recreates target DB, runs
      `pg_restore`
- [ ] CLI: `bin/pito restore:meilisearch <file>` — Meili snapshot import via
      container restart
- [ ] CLI: `bin/pito restore:check` — sanity checks after restore
- [ ] Each restore audits to `log/operational_audit.log`
- [ ] Document in `pito/docs/backup.md`

### Backup management

- [ ] CLI: `bin/pito backup:all` — Postgres + Meili + Redis + KB status,
      sequential
- [ ] CLI: `bin/pito backup:list` — table of files with path/size/age/retention
      bucket
- [ ] CLI: `bin/pito backup:prune` — `--dry-run` default; typed phrase to
      actually delete
- [ ] Specs for retention logic against fixture timestamps

### Off-site upload (optional, configured but not required for Beta laptop dev)

- [ ] Add `BACKUP_REMOTE_*` env var support
- [ ] CLI: `bin/pito backup:upload` — syncs local backup directory to remote
- [ ] Use `rclone` shell-out (simpler than `aws-sdk-s3` for cross-provider use)
- [ ] Off by default; documented for Phase 16 to turn on

### Observability integration

- [ ] Phase 13's `/stats` page gets a "Backup Status" section (added in this
      phase, not retroactively in Phase 13)
- [ ] Last-backup-per-type display
- [ ] Total backup storage used
- [ ] Age warning if > 36 hours; fires Phase 13's threshold banner

### Documentation

- [ ] `pito/docs/backup.md` (new): comprehensive guide — what's backed up,
      where, how to restore, how to test, retention policy, off-site setup,
      master-key handling
- [ ] Update `pito/docs/architecture.md`: backup layer added to the
      architectural reference
- [ ] **Disaster recovery runbook** in `pito/docs/runbook.md` (new): what to do
      if Postgres data corrupted, Meili data corrupted, full laptop loss, master
      key loss

### Restore drill

- [ ] Set up parallel test environment via Docker compose with separate volumes
- [ ] Take fresh backup of laptop Pito
- [ ] Restore everything to the test environment
- [ ] Verify dashboard, search, related queries, KB, auth all work
- [ ] Document drill outcome in `log.md`: how long it took, what surprised, what
      got fixed

### Validation

- [ ] Manual: `bin/pito backup:all` — completes in reasonable time, files appear
      in expected locations
- [ ] Manual: `bin/pito backup:list` — shows all backups with correct retention
      bucket assignment
- [ ] Manual: `bin/pito backup:prune --dry-run` — shows what would be removed;
      no actual deletion
- [ ] Manual: `bin/pito backup:prune` (with typed confirmation) — removes
      outside-retention files; current files preserved
- [ ] **Manual: full restore drill end-to-end (the mandatory drill above)**
- [ ] Manual: stale-backup warning fires when last backup is artificially aged
      (touch a backup file's mtime to simulate)
- [ ] All RSpec specs pass
- [ ] Brakeman, bundler-audit, Dependabot — clean

---

## Specs requirements

- Postgres backup spec: `pg_dump` invocation correct, file output present,
  `pg_restore --list` validates dump.
- Meilisearch backup spec: snapshot API mocked; file copy verified; pollux until
  complete logic.
- Retention prune spec: fixture files with controlled timestamps; correct files
  identified for deletion across all retention buckets (daily, weekly, monthly).
- Restore check spec: fixture data; sanity checks pass and fail correctly.
- KB status spec: clean repo, dirty repo, ahead-of-remote repo each detected
  correctly.
- The restore drill itself isn't a spec — it's a manual checklist with
  documented outcome in `log.md`.

## Security requirements

- Backup files contain ALL data including encrypted columns. Filesystem
  permissions: `chmod 600` on every backup file, `chmod 700` on the backup
  directory tree.
- Off-site uploads use TLS only.
- Restore tools require explicit typed-phrase confirmation (typed words, not
  just "y" — prevents fat-finger disasters).
- **Master key NEVER included in any automated backup.** It's a separate
  concern, documented but not automated. The runbook is explicit about this.
- Audit: every restore action recorded to `log/operational_audit.log` (separate
  file because the Postgres-based audit log gets obliterated by restore).
- Backup files containing encrypted columns are still sensitive — they encrypt
  at the column level, but the backup file itself is decryptable by anyone with
  the master key. Off-site storage providers can see the file metadata, just not
  its contents.
- Brakeman: review shell-out patterns (`pg_dump`, `redis-cli`, `rclone`); use
  safe argument arrays.
- bundler-audit: clean. Verify `aws-sdk-s3` if used (recommend `rclone`
  shell-out instead).
- Dependabot: review.
- `pito/docs/design.md`: backup status section in stats page documented.

## Manual testing checklist

The user runs through this before commit:

1. `bin/pito backup:all` — completes in <2 minutes; files appear in
   `~/Backups/pito/{postgres,meilisearch,redis}/`
2. `bin/pito backup:list` — shows files; retention buckets correctly assigned
3. `bin/pito backup:prune --dry-run` — shows what would be removed; nothing
   actually deleted
4. **Full restore drill:**
   - Start a parallel test environment (separate Docker compose project,
     separate volumes)
   - Take a fresh backup
   - Restore Postgres + Meili + KB to test env
   - Start Pito in test mode against restored data
   - Verify dashboard renders, channels list shows, search works,
     related-content queries return results (proves pgvector indices intact), KB
     content readable, MCP tool calls succeed (proves token encryption keys
     intact)
   - Document what worked, what broke, what got fixed in `log.md`
5. Set off-site config to a test bucket; run `bin/pito backup:upload`; verify
   objects appear in the remote bucket
6. Set Phase 13 threshold for "last backup > 36 hours"; touch a backup file to
   make it look old; verify warning banner fires on `/stats` and `/`
7. `bundle exec rspec` — green

---

## Challenges to anticipate

- **`pg_restore` version compatibility.** Postgres minor versions are
  forward-compatible; restoring across major versions is not. Document the
  version constraint in the runbook (Beta uses Postgres 17 from Phase 2; Hetzner
  deployment in Phase 16 will use the same major version).
- **Meilisearch snapshot exclusivity.** Meili pauses briefly during snapshot.
  Document expected downtime (~seconds for typical index sizes).
- **Vector index rebuild on restore.** pgvector index data is included in
  `pg_dump`'s custom format; `pg_restore` rebuilds indexes which can be slow for
  large vector tables. Time it during the restore drill; document expected
  duration.
- **Master key handling is the most common DR gap.** The user must store the
  master key separately from the backup files. The runbook MUST be explicit.
  Without the master key, the encrypted columns (OAuth tokens, etc.) are
  inaccessible — the database structure restores, but key data is unusable.
- **Restore drill takes time.** End-of-phase drill is significant work; budget
  half a working session for it. Don't skip — backups that haven't been restored
  aren't backups.
- **Backups grow unboundedly without retention enforcement.** Verify the prune
  cron / timer actually runs (tail the timer log). The `prune` command should
  also be in `bin/pito backup:all` with the dry-run flag, surfacing what would
  be cleaned but not actually doing it (operator runs prune separately).
- **Off-site bandwidth cost.** Daily uploads of full Postgres + Meili dumps can
  be hundreds of MB to GB. Hetzner Storage Box / B2 / Wasabi pricing is generous
  for this volume; estimate before turning on. Document expected monthly cost.
- **Both Pumas continue running during backup.** `pg_dump` operates on a
  consistent snapshot internally — both Pumas can keep serving requests during
  backup. Meili snapshot pauses Meili briefly; user-facing search hiccups for
  seconds. Acceptable.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user has space for backups locally (at least 10× current data size on the
   laptop).
2. The user is OK with the retention policy (30 daily / 8 weekly / 6 monthly for
   Postgres + Meili; 7 daily for Redis).
3. Off-site backups in Beta: optional. Confirm whether to set up now
   (recommended for testing the off-site path before Phase 16) or defer entirely
   to Phase 16.
4. The mandatory restore drill is mandatory. The user budgets time for it.
5. Backup tool: shell-out to `pg_dump` directly (recommended for simplicity) vs
   a Ruby gem like `backup` (more abstraction, more dependency surface).
   Recommend shell-out.
6. Off-site sync tool: `rclone` (recommended) vs `aws-sdk-s3` (Ruby-native).
   Confirm.
