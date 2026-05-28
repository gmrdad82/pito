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
# Runtime state restore (capture/restore mechanism)
# ---------------------------------------------------------------------------
#
# Phase 32 follow-up (2026-05-16). When the operator has captured
# runtime DB state into `Rails.application.credentials.runtime_state`
# via `bin/rails pito:state:capture`, this block restores it after a
# `db:drop db:create db:migrate db:seed` cycle so the operator does
# not have to re-enroll TOTP, re-paste webhook URLs, or re-register
# OAuth applications.
#
# Recoverable state: TOTP seed + enrollment stamps, Discord/Slack
# webhook URLs + routing flags, Doorkeeper applications (uid + plain
# secret + redirect_uri + scopes + confidential).
#
# Irrecoverable, always regenerated: TOTP backup codes (BCrypt-hashed
# in DB), dev ApiToken plaintext (HMAC+pepper digest). Both print
# ONCE to STDOUT on this seed run.
#
# Ordering: this block runs BEFORE the Claude Desktop OAuth seed
# below. If the captured `runtime_state.oauth_apps` includes the
# `claude-mcp` row, restoring it here makes the find-by-name lookup
# in the Claude seed block hit the captured row and skip its own
# create branch — so the operator's real client_id + secret survive
# the reseed instead of being clobbered by a fresh random uid.
#
# Boolean fields cross the captured-YAML boundary as "yes" / "no"
# strings per CLAUDE.md hard rule; `YesNo.from_yes_no` converts back.
#
# Absent `runtime_state` block: this entire branch is a no-op and the
# seed behaves exactly as it did before the capture/restore mechanism
# landed.

if (runtime_state = Rails.application.credentials.runtime_state)
  puts ""
  puts "restoring runtime state from credentials..."

  # ----- TOTP -----
  totp_cfg = runtime_state[:totp]
  if totp_cfg.present? && totp_cfg[:seed].present? && owner.present?
    owner.update!(
      totp_seed_encrypted: totp_cfg[:seed],
      totp_enabled_at:     totp_cfg[:enabled_at],
      totp_disabled_at:    totp_cfg[:disabled_at]
    )
    puts "  TOTP enrollment restored for #{owner.username}."

    # Backup codes are BCrypt-hashed in the DB — the plaintext can't
    # be lifted out at capture time, so they're regenerated here and
    # shown once. Mirrors the dev-token "save this now" banner.
    if owner.totp_enabled?
      fresh_codes = Pito::Auth::BackupCodeRegenerator.call(
        user:           owner,
        acting_user:    owner,
        source_surface: :tui
      )
      puts ""
      puts "=" * 64
      puts "TOTP restored — NEW backup codes (save these now, cannot be"
      puts "retrieved later):"
      puts ""
      fresh_codes.each { |code| puts "  #{code}" }
      puts ""
      puts "=" * 64
      puts ""
    end
  end

  # ----- Webhooks -----
  #
  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The per-brand `everything` /
  # `daily_digest` columns were dropped in favour of two shared
  # toggles on `AppSetting.singleton_row`. The captured payload still
  # carries the legacy per-brand keys (older runtime_state snapshots);
  # we OR them into the shared toggles during restore for intent
  # preservation, then move on. New captures (post-this-commit)
  # advertise the shared shape directly under `runtime_state[:notifications]`.
  any_everything   = false
  any_daily_digest = false

  %i[discord slack].each do |kind|
    cfg = runtime_state.dig(:webhooks, kind)
    next if cfg.blank? || cfg[:webhook_url].blank?

    record = NotificationDeliveryChannel.find_or_initialize_by(kind: kind.to_s)
    record.webhook_url       = cfg[:webhook_url]
    record.last_validated_at = cfg[:last_validated_at]
    record.save!

    any_everything   ||= YesNo.from_yes_no(cfg[:everything])    if cfg.key?(:everything)
    any_daily_digest ||= YesNo.from_yes_no(cfg[:daily_digest])  if cfg.key?(:daily_digest)

    puts "  webhook[#{kind}] restored."
  end

  # Shared toggles — prefer the new `notifications` block when present;
  # fall back to the OR of the legacy per-brand flags.
  shared = runtime_state[:notifications]
  if shared.is_a?(Hash)
    AppSetting.set_notification_toggle!(:notifications_send_all,
      YesNo.from_yes_no(shared[:send_all]))
    AppSetting.set_notification_toggle!(:notifications_send_daily_digest,
      YesNo.from_yes_no(shared[:send_daily_digest]))
    puts "  notifications shared toggles restored " \
         "(send_all=#{shared[:send_all]}, send_daily_digest=#{shared[:send_daily_digest]})."
  elsif any_everything || any_daily_digest
    AppSetting.set_notification_toggle!(:notifications_send_all, any_everything)
    AppSetting.set_notification_toggle!(:notifications_send_daily_digest, any_daily_digest)
    puts "  notifications shared toggles seeded from legacy per-brand flags " \
         "(send_all=#{any_everything ? 'yes' : 'no'}, " \
         "send_daily_digest=#{any_daily_digest ? 'yes' : 'no'})."
  end

  puts "runtime state restore complete."
end

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
# Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — `gog` and `epic`
# seeds were removed: GoG, Epic, and Steam now share the single `steam`
# canonical row + Steam logo for the "PC" umbrella. `xbox` stays for
# future console work but does not currently surface a chip or logo.
#
# Idempotency note: lookup is by `name`, NOT `slug`. Platform uses
# FriendlyId with `should_generate_new_friendly_id?` returning
# `will_save_change_to_name?`, so the `before_validation` callback
# regenerates `slug` from `name` on every create — a row inserted with
# `slug: "ps5"` ends up persisted as `slug: "playstation-5"`. Looking
# up by `slug:` on subsequent seed runs would miss the existing row
# and insert a duplicate. `name` is the stable natural key here (it is
# what FriendlyId derives the slug from in the first place).
[
  { name: "PlayStation 5" },
  { name: "Nintendo Switch 2" },
  { name: "Steam" },
  { name: "Xbox" }
].each do |attrs|
  Platform.unscoped.find_or_create_by!(name: attrs[:name])
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

# ---------------------------------------------------------------------------
# 2026-05-25 — Upcoming-games demo seed (dev / demo only)
# ---------------------------------------------------------------------------
#
# Populates the home-screen "upcoming games" panel with owned games
# whose `release_date` lands inside the upcoming 30-day window. Self-
# guarded against production via an env check in the loaded file so
# accidentally running it on prod is a no-op.
#
# Idempotent across reruns — re-seeding shifts the demo titles' release
# dates forward so the panel stays "alive" without manual maintenance.

load Rails.root.join("db/seeds/upcoming_games_demo.rb")

puts "done!"
