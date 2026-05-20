# Phase 32 follow-up (2026-05-16). Runtime-state capture + restore.
#
# Purpose: make `bin/rails db:drop db:create db:migrate db:seed` a
# zero-loss operation for the post-bootstrap configuration that an
# operator carefully wired up by hand — TOTP enrollment, webhook URLs,
# OAuth applications. Without this surface every reseed forced the
# operator through the enrollment + paste + register dance again.
#
# Source of truth is the database. The capture rake task reads the
# live DB, lifts the recoverable fields into a `runtime_state:` block
# inside `Rails.application.credentials`, and `db:seed` then conditionally
# restores from that block on next boot.
#
# Recoverable fields (AR-Encryption-decryptable or Doorkeeper-plain):
#   * `User.first.totp_seed_encrypted` + `totp_enabled_at`
#   * Discord + Slack `NotificationDeliveryChannel` rows (webhook URL +
#     routing flags + last_validated_at)
#   * Every `OauthApplication` row (uid + plain secret + redirect_uri +
#     scopes + confidential flag)
#
# Irrecoverable (regenerated on each seed — printed once):
#   * TOTP backup codes (BCrypt-hashed; the plaintext is gone)
#   * The dev `ApiToken` plaintext (HMAC+pepper-digested; gone)
#
# Boundary convention: booleans inside the captured YAML cross the
# install boundary as "yes" / "no" strings (CLAUDE.md hard rule).
# Internal Ruby state stays Boolean; conversion happens at the YAML
# write (capture) and the YAML read (seed restore).
#
# Defensive write pattern: snapshot the existing top-level credential
# keys; back up `config/credentials.yml.enc` to `tmp/` before writing;
# verify the written file decrypts AND retains every original top-level
# key; restore from backup if any check fails. Operator-friendly stdout
# at every step, NO secret values ever printed.
#
# Usage:
#   bin/rails pito:state:capture
#
# Re-run is idempotent: an existing `runtime_state:` block is replaced
# wholesale with current DB state — never merged.

require "yaml"
require "fileutils"

namespace :pito do
  namespace :state do
    desc "Capture runtime DB state (TOTP, webhooks, OAuth apps) into " \
         "credentials.runtime_state so the next db:seed restores it. " \
         "Idempotent — overwrites the prior capture. Never prints secrets."
    task capture: :environment do
      PitoStateCapture.call
    end

    # Phase 32 follow-up (2026-05-16) — operator escape hatch for the
    # reindex three-layer lock. If the Sidekiq worker crashed mid-
    # reindex the DB flag (`AppSetting.reindex_running`) stays true
    # and the UI keeps showing the `dot-loader` indicator forever.
    # This task clears the flag so the next operator click on
    # `[reindex]` is accepted. Idempotent.
    desc "Clear the reindex DB lock (use when ReindexAllJob crashed " \
         "mid-run and the UI is stuck on the in-progress indicator)."
    task clear_reindex_lock: :environment do
      AppSetting.clear_reindex_lock!
      puts "reindex lock cleared (reindex_running=false, " \
           "reindex_started_at=nil)."
    end
  end
end

# Capture orchestrator. Reads the live DB, builds the YAML payload,
# rewrites `config/credentials.yml.enc` with the new `runtime_state:`
# block spliced in, then verifies the write round-tripped. On any
# failure restores from the on-disk backup.
module PitoStateCapture
  module_function

  CREDENTIALS_PATH = Rails.root.join("config/credentials.yml.enc")
  BACKUP_DIR       = Rails.root.join("tmp")

  def call
    user = User.first
    if user.nil?
      warn "no User row present — nothing to capture. Seed the DB first."
      exit 1
    end

    payload = build_payload(user)
    print_capture_summary(payload)

    encrypted = Rails.application.credentials
    backup_path = backup_credentials_file!

    begin
      original_yaml = encrypted.read
      pre_keys     = top_level_keys(original_yaml)

      merged_yaml  = splice_runtime_state(original_yaml, payload)

      encrypted.write(merged_yaml)

      # Verify: the file must still parse, must still carry every
      # pre-existing top-level key, AND must carry the new
      # `runtime_state` block. Any deviation triggers the restore path.
      verify_round_trip!(pre_keys)
    rescue StandardError => e
      restore_from_backup!(backup_path)
      warn "ERROR: capture failed — credentials restored from backup."
      warn "  #{e.class}: #{e.message}"
      exit 1
    end

    puts ""
    puts "credentials.runtime_state written. Next `db:seed` will restore."
    puts "backup retained at: #{backup_path}"
    puts ""
    puts "IRRECOVERABLE (regenerated on next seed, shown once):"
    puts "  * TOTP backup codes (BCrypt-hashed in DB — plaintext gone)."
    puts "  * dev ApiToken plaintext (HMAC+pepper digest — plaintext gone)."
  end

  # ---------------------------------------------------------------------
  # Payload construction
  # ---------------------------------------------------------------------

  # Build the symbol-keyed Hash that becomes the YAML `runtime_state:`
  # block. Booleans cross the boundary as "yes" / "no" strings per
  # CLAUDE.md; timestamps as ISO8601 UTC; webhook URLs and TOTP seed as
  # AR-decrypted plaintext (the value pito feeds to ROTP / the HTTPS
  # POST). Doorkeeper application `secret` is plaintext because the
  # default strategy is `:plain` (the same plaintext the create-page
  # surface returns on first creation).
  def build_payload(user)
    {
      totp:          totp_payload(user),
      webhooks:      webhooks_payload,
      notifications: notifications_payload,
      oauth_apps:    oauth_apps_payload
    }
  end

  def totp_payload(user)
    return {} if user.totp_seed_encrypted.blank?

    {
      seed:         user.totp_seed_encrypted,
      enabled_at:   user.totp_enabled_at&.utc&.iso8601,
      disabled_at:  user.totp_disabled_at&.utc&.iso8601
    }.compact
  end

  def webhooks_payload
    payload = {}

    %i[discord slack].each do |kind|
      record = NotificationDeliveryChannel.send(kind)
      next if record.nil? || record.webhook_url.blank?

      payload[kind] = {
        webhook_url:       record.webhook_url,
        last_validated_at: record.last_validated_at&.utc&.iso8601
      }.compact
    end

    payload
  end

  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The two shared notification
  # toggles live on `AppSetting.singleton_row`. Capture them under a
  # dedicated `notifications` block (separate from per-brand
  # `webhooks`) so the seed restore path can read them by name.
  def notifications_payload
    {
      send_all:          YesNo.to_yes_no(AppSetting.notifications_send_all?),
      send_daily_digest: YesNo.to_yes_no(AppSetting.notifications_send_daily_digest?)
    }
  end

  def oauth_apps_payload
    OauthApplication.order(:created_at).map do |app|
      {
        name:         app.name,
        uid:          app.uid,
        secret:       app.secret,
        redirect_uri: app.redirect_uri,
        scopes:       app.scopes.to_s,
        confidential: YesNo.to_yes_no(app.confidential?)
      }
    end
  end

  # ---------------------------------------------------------------------
  # YAML splice
  # ---------------------------------------------------------------------

  # Merge the new `runtime_state:` block into the existing decrypted
  # YAML body, preserving every other top-level key untouched. The
  # underlying YAML library does not preserve YAML comments through a
  # parse + emit cycle; this is consistent with how `credentials:edit`
  # itself behaves, so the round-trip is the same lossiness the
  # operator already accepts when editing by hand.
  def splice_runtime_state(yaml_string, payload)
    parsed = yaml_string.to_s.strip.empty? ? {} : (YAML.safe_load(yaml_string, permitted_classes: [ Symbol, Date, Time ]) || {})
    parsed = parsed.deep_stringify_keys

    parsed["runtime_state"] = payload.deep_stringify_keys

    parsed.to_yaml
  end

  # ---------------------------------------------------------------------
  # Verification + backup / restore
  # ---------------------------------------------------------------------

  def top_level_keys(yaml_string)
    parsed = yaml_string.to_s.strip.empty? ? {} : (YAML.safe_load(yaml_string, permitted_classes: [ Symbol, Date, Time ]) || {})
    parsed.keys.map(&:to_s).sort
  end

  def backup_credentials_file!
    FileUtils.mkdir_p(BACKUP_DIR)
    stamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
    backup_path = BACKUP_DIR.join("credentials.yml.enc.bak-#{stamp}")
    FileUtils.cp(CREDENTIALS_PATH, backup_path) if File.exist?(CREDENTIALS_PATH)
    backup_path
  end

  def restore_from_backup!(backup_path)
    return unless File.exist?(backup_path)
    FileUtils.cp(backup_path, CREDENTIALS_PATH)
  end

  # Re-decrypt the file we just wrote, then ensure the post-write
  # top-level key set is a superset of pre-write keys AND carries
  # `runtime_state`. Either failure raises and triggers the
  # restore-from-backup path in `call`.
  def verify_round_trip!(pre_keys)
    # Force a fresh read of the file we just wrote — the existing
    # `Rails.application.credentials` object may have memoized values
    # from before our write.
    fresh = Rails.application.encrypted(CREDENTIALS_PATH)
    written_yaml = fresh.read
    written_keys = top_level_keys(written_yaml)

    missing = pre_keys - written_keys
    raise "post-write credentials lost top-level keys: #{missing.join(', ')}" if missing.any?

    raise "post-write credentials missing `runtime_state` block" unless written_keys.include?("runtime_state")
  end

  # ---------------------------------------------------------------------
  # Operator-facing stdout (NO secret values — counts and names only)
  # ---------------------------------------------------------------------

  def print_capture_summary(payload)
    puts "capturing runtime state from live DB..."

    if payload[:totp].any?
      stamps = []
      stamps << "enabled_at=#{payload[:totp][:enabled_at]}"  if payload[:totp][:enabled_at]
      stamps << "disabled_at=#{payload[:totp][:disabled_at]}" if payload[:totp][:disabled_at]
      puts "  * TOTP enrollment present (#{stamps.join(', ')})."
    else
      puts "  * no TOTP enrollment on User.first — skipping totp block."
    end

    webhook_count = payload[:webhooks].size
    if webhook_count.zero?
      puts "  * no Discord/Slack webhook rows — skipping webhooks block."
    else
      payload[:webhooks].each_key do |kind|
        puts "  * webhook[#{kind}] captured."
      end
    end

    notifications = payload[:notifications] || {}
    puts "  * notifications shared toggles: " \
         "send_all=#{notifications[:send_all]}, " \
         "send_daily_digest=#{notifications[:send_daily_digest]}."

    app_count = payload[:oauth_apps].size
    if app_count.zero?
      puts "  * no Doorkeeper applications — skipping oauth_apps block."
    else
      puts "  * #{app_count} Doorkeeper application#{'s' unless app_count == 1} to capture:"
      payload[:oauth_apps].each do |app|
        puts "      - #{app[:name]} " \
             "(client_id=#{app[:uid]}, confidential=#{app[:confidential]})"
      end
    end
  end
end
