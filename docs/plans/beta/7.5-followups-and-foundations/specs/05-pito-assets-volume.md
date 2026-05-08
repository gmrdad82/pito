# Phase 7.5 — Step 05 — `pito-assets` Docker Volume

> Implementation-ready spec. Adds a third Docker named volume to the compose
> stack alongside `pito-postgres-data`, `pito-redis-data`, and
> `pito-meilisearch-data`. The new volume — `pito-assets` — holds Pito-managed
> binary assets: game cover art today (already on Active Storage; this spec
> moves the storage root onto the named volume), footage thumbnails (Phase 7.5
> step 06), and future thumbnail surfaces.

---

## Goal

Stand up a dedicated, pito-identifiable Docker volume for app-managed binary
assets, distinct from the read-only Mobile capture surface (`pito_notes`) and
from source-footage paths (those stay catalog-only, referenced by absolute path
on the host filesystem; never copied into Pito).

The volume is the home for:

- Active Storage's `:local` service root — the existing Game `cover_art`
  attachments, plus future Channel banner / Channel avatar / Video thumbnail
  attachments when those phases land.
- Footage thumbnail extracted frames (Phase 7.5 step 06).
- Anything else Pito persists that is bytes-not-rows.

## Scope boundary

What `pito-assets` is:

- A Docker named volume mounted at `/var/lib/pito-assets` inside the Rails
  container.
- The on-disk root for `Active Storage`'s `:local` service.
- The on-disk root for `Pito::AssetsRoot` — a thin module that resolves an
  absolute path for non-Active-Storage byte writes (footage thumbnails are the
  first consumer in step 06).

What `pito-assets` is NOT:

- Not a copy of source footage. The footage importer indexes paths on the host
  filesystem (`Footage#local_path`) but never copies bytes off the user's drive
  into Pito.
- Not a Mobile capture surface. `docs/notes/` and the Mobile-via-MCP `save_note`
  path use `pito-notes`, which is separate.
- Not a Postgres backup target.

## Files touched

### Compose / volumes

- `compose.yml` (or `docker-compose.yml` — match the existing filename) — add
  the third named volume:
  ```yaml
  volumes:
    pito-postgres-data:
      name: pito-postgres-data
    pito-redis-data:
      name: pito-redis-data
    pito-meilisearch-data:
      name: pito-meilisearch-data
    pito-assets:
      name: pito-assets
  ```
- The Rails container service mounts `pito-assets` at `/var/lib/pito-assets`
  (read-write). The Sidekiq worker container (if separate) mounts it too — image
  processing for Active Storage variants happens in the worker.

### Active Storage configuration

- `config/storage.yml` — point `:local`'s root at the new env-driven path:
  ```yaml
  local:
    service: Disk
    root: <%= ENV.fetch("PITO_ASSETS_PATH", "/var/lib/pito-assets") %>
  ```
- Q7 default = env-var-driven (mirrors `PITO_NOTES_PATH`). If Q7 flips to
  "hard-code", drop the `ENV.fetch` and pin `/var/lib/pito-assets`.

### Test environment carve-out

- `config/environments/test.rb` retains `config.active_storage.service = :test`
  per the Phase 4 spec amendment. Test attachments write to `tmp/storage`, not
  to `pito-assets`. This spec does not change that.

### `Pito::AssetsRoot` helper (new)

- `app/lib/pito/assets_root.rb` — analogous to `app/lib/dev_doc_path.rb` for the
  Mobile capture surface. Provides:
  - `Pito::AssetsRoot.path(*segments)` — returns an absolute `Pathname` under
    the assets root, with lexical containment (`Pathname#cleanpath`) to reject
    traversal.
  - `Pito::AssetsRoot.ensure_dir!(*segments)` — `mkdir_p` shorthand.
  - `Pito::AssetsRoot.tenant_root(tenant)` — returns
    `<assets_root>/<tenant_id>/`. Mirrors the `<NOTES_VOLUME>/<tenant_id>/`
    shape the notes surface uses.
- `spec/lib/pito/assets_root_spec.rb` — path-safety asserts (no traversal
  escape), `tenant_root` returns the right shape, `ensure_dir!` is idempotent.

### Setup / teardown

- `bin/setup` — touch the volume on first install (the `docker volume create` is
  implicit when compose runs, but `bin/setup` should make sure the path exists
  inside the container).
- `docs/setup.md` — extend the local-port + volume table to include
  `pito-assets`. (The docs-keeper agent handles this in a follow-up dispatch —
  out of this spec's lane.)

### Migration of existing Active Storage data (if any)

The current `:local` service root is whatever Rails defaulted to (`storage/`
under the Rails root, or whatever the prior `storage.yml` says). On the user's
machine, this likely has the existing Game cover art uploads from Phase 4.

Migration approach (one-shot, on the user's box, not a CI step):

1. Inspect current root:
   `bin/rails runner 'puts Rails.application.config.active_storage.service_configurations.fetch("local").fetch("root")'`.
2. If non-empty, the user copies the existing files to the new volume location
   once: `cp -a <old_root>/. /var/lib/pito-assets/`.
3. If running in `bin/dev` outside Docker, the user creates
   `/var/lib/pito-assets/` on the host with appropriate ownership (or sets
   `PITO_ASSETS_PATH` to a path they already control).
4. Verify Active Storage finds the files: load a Game show page that has a
   cover_art; the variant should render.

Documented as a manual step in §"Manual test recipe" — not automated in this
dispatch.

### Specs

- `spec/lib/pito/assets_root_spec.rb` — already noted above.
- Existing Active Storage specs continue to pass (`:test` service isolation
  means specs do not exercise `pito-assets`; the system specs that upload a
  cover_art still write to `tmp/storage`).

## Acceptance

- [ ] `compose.yml` lists `pito-assets` alongside the other three named volumes,
      with explicit `name:` overrides.
- [ ] Rails container mounts `pito-assets` at `/var/lib/pito-assets` (rw).
- [ ] Sidekiq worker container (if it has its own service) also mounts the
      volume.
- [ ] `config/storage.yml`'s `:local` root resolves via
      `ENV.fetch("PITO_ASSETS_PATH", "/var/lib/pito-assets")` (Q7 = env var) OR
      pins to `/var/lib/pito-assets` (Q7 = hard-code).
- [ ] `config/environments/test.rb` continues to use `:test` service;
      `tmp/storage` writes are unaffected.
- [ ] `Pito::AssetsRoot` exists with path-safety semantics matching `DevDocPath`
      (lexical `cleanpath`, traversal rejected).
- [ ] `Pito::AssetsRoot.tenant_root(tenant)` returns the
      `<assets_root>/<tenant_id>` shape.
- [ ] `bundle exec rspec spec/lib/pito/assets_root_spec.rb` green.
- [ ] On a fresh `bin/setup` + `bin/dev`, the user can upload a Game cover_art,
      the file lands under `/var/lib/pito-assets/` (verify on host:
      `docker exec <container> ls -lah     /var/lib/pito-assets/active_storage/...`),
      and the variant renders.

## Manual test recipe

Prereq: stop `bin/dev`, back up the existing `storage/` directory if it has
files you care about (Game cover art uploads).

1. Pull the change. Run `bin/setup`. Confirm `docker volume ls | grep pito-`
   shows four volumes including `pito-assets`.
2. Start `bin/dev`. The Rails container should start cleanly; no Active Storage
   error on boot.
3. (One-time migration) From the host:
   `cp -a <old-storage-root>/. /var/lib/pito-assets/` (or the docker-volume
   equivalent). Skip if you don't have prior uploads.
4. Visit an existing Game show page that has a cover_art. The image renders.
5. Upload a NEW cover_art on a Game edit page. The file lands under the new
   volume:
   ```bash
   docker exec <rails-container> find /var/lib/pito-assets -type f -newer /tmp/marker
   ```
   (Set `/tmp/marker` to before the upload first via `touch`.)
6. `bin/rails runner 'puts Pito::AssetsRoot.path("test", "ok").to_s'` prints
   `/var/lib/pito-assets/test/ok`.
7. `bin/rails runner 'Pito::AssetsRoot.path("..", "etc")'` raises the
   traversal-rejection error.
8. `bundle exec rspec spec/lib/pito/assets_root_spec.rb` green.

## Cross-stack scope

- Rails — **in scope.**
- Docker / compose — **in scope.**
- `pito` CLI — **out of scope.** The CLI doesn't read or write the assets
  volume.
- MCP — **out of scope.** No MCP tool reads or writes `pito-assets`.
- Cloudflare Pages website — **out of scope.**

## Open questions

- **Q7** (from `00-phase-overview.md`) — env-var-driven path
  (`PITO_ASSETS_PATH`) or hard-coded `/var/lib/pito-assets`? Default = env var
  (mirrors `PITO_NOTES_PATH`).

## Follow-ups created

- **Hetzner cutover.** When Phase 16 / Hetzner ships, the `pito-assets` volume
  points at a managed volume. Same shape as `pito-postgres-data` etc. Park under
  the Hetzner-prep follow-up.
- **Active Storage retention sweep.** Once Pito holds enough uploaded bytes to
  matter, a "purge orphaned blobs" rake task is worth adding (Active Storage's
  `purge` mechanic via the `analyze_now` job). Park as a follow-up under "asset
  hygiene".

## Decisions (locked)

- **One volume for Pito-managed binary assets.** No separate per-feature volume.
  Game cover art, footage thumbnails, future channel banners — all under one
  root.
- **Tenant-scoped subdirectories.** Anything under `pito-assets` that is
  tenant-scoped uses the `<assets_root>/<tenant_id>/<feature>/...` layout.
  Active Storage manages its own internal layout under
  `<assets_root>/active_storage/...` and is NOT subject to the tenant-prefix
  rule (Active Storage's existing path scheme is the source of truth for its own
  data).
- **No copies of source footage.** ADR-style: Pito does NOT copy user-recorded
  video bytes into `pito-assets`. Footage thumbnails (step 06) are derived
  assets, not copies of source. The `Footage#local_path` column continues to
  point at the user's drive; thumbnails go under `pito-assets`.
- **Test environment is unaffected.** Tests stay on `:test` / `tmp/storage` for
  spec isolation. The volume only matters for development and production.
