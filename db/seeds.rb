# Seed data for development — run with: bin/rails db:seed
# Idempotent: safe to run multiple times.
#
# Phase 8 — Tenant Drop + Email-Only Login (ADR 0003). The seed reads
# `Rails.application.credentials.owner.{email, password}` only; there
# is no Tenant model, no `username`, no `tenant_name` / `tenant_slug`.

puts "seeding app settings..."
AppSetting.set("max_panes", "5")
AppSetting.set("pane_title_length", "14")
puts "  max_panes = 5, pane_title_length = 14"

# Phase 13.2 — Analytics sync engine. The monetization flag is an
# AppSetting (master-agent decision 8: schema-ready, sync-disabled by
# default). Idempotent — only seed if the row is missing so existing
# installs that have flipped it on don't get clobbered. Boolean
# crosses the AppSetting key/value boundary as the canonical
# yes/no string per CLAUDE.md.
AppSetting.find_or_create_by!(key: "monetization_enabled") do |setting|
  setting.value = "no"
end
puts "  monetization_enabled = no (initial)"

# Phase 4 §3.5 (Phase B revamp, 2026-05-04) — Voyage AppSetting bootstrap.
# The key is sourced from Rails credentials during seeding so initial
# deployments work without manual UI entry. Once the app reaches Hetzner
# (Phase 16), credentials will hold the key only as a bootstrap fallback,
# and the UI becomes the authoritative source. Idempotent — re-running
# seeds does NOT clobber a key the user has already set, and the flag
# only flips on in production once the key is present.
if AppSetting.exists?
  setting = AppSetting.first
  if setting.voyage_api_key.blank?
    creds_key = Rails.application.credentials.dig(:voyage, Rails.env.to_sym, :api_key)
    if creds_key.present?
      setting.update!(voyage_api_key: creds_key)
      puts "  voyage_api_key seeded from credentials"
    end
  end
  if Rails.env.production? && setting.voyage_api_key.present? && !setting.voyage_index_project_notes
    setting.update!(voyage_index_project_notes: true)
    puts "  voyage_index_project_notes = true (production)"
  end
end

# ---------------------------------------------------------------------------
# Owner credentials (User)
# ---------------------------------------------------------------------------

owner_creds = Rails.application.credentials.dig(:owner)
if owner_creds.blank?
  puts "  WARNING: credentials :owner block missing; using placeholder values."
  puts "           run `bin/rails credentials:edit` to populate :owner with"
  puts "           email and password."
end

owner_email    = owner_creds&.dig(:email).presence || "owner@example.test"
owner_password = owner_creds&.dig(:password).presence || "change-me-please"

puts "seeding owner user..."
owner = User.find_or_initialize_by(email: owner_email)
owner.password = owner_password
owner.password_confirmation = owner_password
owner.save!
puts "  user: #{owner.email} (id=#{owner.id})"

# Phase 3 — Step C (5c-settings-ui-and-docs.md). Seed a default `dev` API
# token so the install ceremony captures plaintext once. Idempotent — second
# `db:seed` finds the existing row and is a no-op (the dev plaintext is gone
# forever after the first run; revoke + mint a new one if you lost it).
#
# Phase 10 — MCP scope simplification (ADR 0004). The dev token now
# carries the full `Scopes::ALL` set (`["dev", "app"]` in development).
# Skipped entirely in production: a production install does not want a
# "dev" token sitting in the database — the operator mints their own
# via `/settings/tokens` with the `app` scope only.
if Rails.env.production?
  puts "  skipping dev token seed (production env)."
elsif !ApiToken.exists?(name: "dev")
  Current.user = owner
  pepper = Rails.application.credentials.dig(:tokens, :pepper)
  if pepper.blank?
    if Rails.env.development?
      # Local dev needs the pepper — halt with the helpful message so the
      # user knows exactly which credential to add and how to generate it.
      abort <<~MSG

        ERROR: cannot seed dev token — :tokens.pepper credential is missing.

        Run: bin/rails credentials:edit
        Add:
          tokens:
            pepper: <64-char hex>

        Generate a value with: openssl rand -hex 32
      MSG
    else
      # Test/CI/production-without-pepper: the dev token is a developer
      # convenience, not a runtime requirement. Skip and warn so seeds run
      # to completion (CI does not set master.key, by design).
      warn "  WARNING: :tokens.pepper missing; skipping dev token seed (#{Rails.env})."
    end
  else
    _token, plaintext = ApiToken.generate!(
      user:   owner,
      name:   "dev",
      scopes: Scopes::ALL.dup
    )
    puts ""
    puts "=" * 64
    puts "Dev token minted (save this now — cannot be shown again):"
    puts plaintext
    puts "=" * 64
    puts ""
  end
end

# ---------------------------------------------------------------------------
# Channels + videos are no longer seeded.
#
# 2026-05-10 — seeded placeholder channels (the 100-row deterministic batch
# plus their per-channel video + stats fan-out) were dropped permanently.
# The Channels and Videos workspaces now bootstrap from real OAuth
# connections via `/settings/youtube`. The cleanup of any existing
# placeholder rows lives in `bin/rails pito:drop_seeded_channels` so
# the operation is idempotent + auditable.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Phase 27 §1a — Platform reference seeds
# ---------------------------------------------------------------------------
#
# Five canonical platforms so the per-platform-ownership editor and the
# filter row have something to bind against before the IGDB platform
# sync runs for the first time. Idempotent — `find_or_create_by!`
# guards repeat runs; subsequent IGDB sync fills `igdb_id` when those
# rows match upstream.

puts "seeding platforms..."
[
  { slug: "ps5",      name: "PlayStation 5",     abbreviation: "PS5" },
  { slug: "switch2",  name: "Nintendo Switch 2", abbreviation: "Switch 2" },
  { slug: "steam",    name: "Steam",             abbreviation: "Steam" },
  { slug: "gog",      name: "GOG",               abbreviation: "GOG" },
  { slug: "epic",     name: "Epic Games Store",  abbreviation: "Epic" }
].each do |attrs|
  Platform.unscoped.find_or_create_by!(slug: attrs[:slug]) do |p|
    p.name = attrs[:name]
    p.abbreviation = attrs[:abbreviation]
  end
end
puts "  #{Platform.unscoped.count} platform rows present."

# ---------------------------------------------------------------------------
# Phase 4 — Project Workspace sample data
# ---------------------------------------------------------------------------
#
# Seeds one Collection, one Game (with cover art attached from
# spec/fixtures/files/cover_art.jpg), one Project that references the Game and
# the Collection, one Note (`last_modified_at` mirrors the row's creation), and
# one Timeline in the initial `editing` state. Idempotent — `find_or_*` calls
# guard against repeat runs.

puts "seeding project workspace sample..."

collection = Collection.find_or_create_by!(name: "Demo Collection")

game = Game.find_or_initialize_by(title: "Demo Game")
game.collection ||= collection
game.publisher  ||= "Demo Studios"
game.platforms = [ { "platform" => "PS5", "owned" => true, "recorded_on" => true } ] if game.platforms.blank?
game.save!

cover_fixture_path = Rails.root.join("spec/fixtures/files/cover_art.jpg")
if cover_fixture_path.exist? && !game.cover_art.attached?
  game.cover_art.attach(
    io: File.open(cover_fixture_path),
    filename: "cover_art.jpg",
    content_type: "image/jpeg"
  )
end

project = Project.find_or_create_by!(name: "Demo Project")

# Polymorphic references — Project -> Game and Project -> Collection.
ProjectReference.find_or_create_by!(
  project: project,
  referenceable_type: "Game", referenceable_id: game.id
)
ProjectReference.find_or_create_by!(
  project: project,
  referenceable_type: "Collection", referenceable_id: collection.id
)

# Sample Note — disk file is NOT created here (NoteSyncJob does that in
# Phase B). The DB row alone is enough for Phase A's smoke test.
Note.find_or_create_by!(
  project: project, path: "demo-note.md"
) do |note|
  note.title = "Demo note"
  note.last_modified_at = Time.current
end

# Sample Timeline in the initial state (aasm `editing`).
Timeline.find_or_create_by!(project: project, title: "Demo Timeline") do |t|
  t.state = :editing
end

puts "  1 collection, 1 game (with cover art), 1 project (2 references), 1 note, 1 timeline"

puts "done!"
