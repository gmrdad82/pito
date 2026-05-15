# Seed data for development — run with: bin/rails db:seed
# Idempotent: safe to run multiple times.
#
# Phase 29 — Unit A2. User auth refactor. The seed reads
# `Rails.application.credentials.owner.{username, password}` only;
# there is no Tenant model, no email, no `tenant_name` /
# `tenant_slug`. The seeded owner has no TOTP configured, so their
# first login is gated straight into TOTP setup by the mandatory-2FA
# gate (`Sessions::AuthConcern#require_totp_configured!`).

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

# Phase 29 — Unit A1. The Voyage API key moved back into
# `Rails.application.credentials.voyage` (per-environment block) — it
# is no longer an AppSetting column, so there is nothing to bootstrap
# here. The non-secret `voyage_index_project_notes` flag stays on the
# AppSetting row; in production it flips on once a Voyage key is
# present in credentials (`AppSetting.voyage_configured?` checks the
# credentials presence). Idempotent — only flips a flag that is still
# off.
if Rails.env.production? && AppSetting.exists? && AppSetting.voyage_configured?
  setting = AppSetting.first
  unless setting.voyage_index_project_notes
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
  puts "           username and password."
end

owner_username = owner_creds&.dig(:username).presence || "owner"
owner_password = owner_creds&.dig(:password).presence || "change-me-please"

puts "seeding owner user..."
owner = User.find_or_initialize_by(username: owner_username)
owner.password = owner_password
owner.password_confirmation = owner_password
owner.save!
puts "  user: #{owner.username} (id=#{owner.id})"

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
  { slug: "epic",     name: "Epic Games Store",  abbreviation: "Epic" },
  { slug: "xbox",     name: "Xbox",              abbreviation: "Xbox" }
].each do |attrs|
  Platform.unscoped.find_or_create_by!(slug: attrs[:slug]) do |p|
    p.name = attrs[:name]
    p.abbreviation = attrs[:abbreviation]
  end
end
puts "  #{Platform.unscoped.count} platform rows present."

# ---------------------------------------------------------------------------
# Sample data (project workspace + "now playing" collection)
# ---------------------------------------------------------------------------
#
# 2026-05-14 — Phase 29 Unit A2 removed the project-workspace sample
# block (Collection / Game / Project / ProjectReference / Note /
# Timeline) and the "now playing" demo Collection. A fresh seed no
# longer creates any Channel, Video, Project, Game, Collection, Note,
# or Timeline rows — those surfaces bootstrap from real data. Channels
# and videos were already dropped from the seed on 2026-05-10.
# ---------------------------------------------------------------------------

puts "done!"
