# Phase 32 follow-up (2026-05-16). 2FA / TOTP enrollment surface.
#
# After the 2026-05-16 cleanup the surface collapsed to a single
# focused enrollment view. Mandatory-2FA means there is no "manage"
# page, no `[disable]` web action, and no `[manage backup codes]`
# control — those are operator-only via rake tasks
# (`pito:user:reset_totp`, `pito:user:regenerate_backup_codes`).
#
# Two actions:
#
#   - `new`    (GET /settings/security/totp) — renders the 2-row
#              focused-dialog enrollment view. Generates a fresh
#              draft (seed + 10 plaintext backup codes) per load and
#              stashes it in `Rails.cache` keyed on the user id. The
#              database row is NOT touched on GET — the draft lives
#              entirely server-side and self-expires in 5 minutes.
#
#   - `create` (POST /settings/security/totp) — atomic-finalize. Reads
#              the draft from the cache, verifies the submitted
#              6-digit code against the cached seed, and ONLY on a
#              correct verify writes `totp_seed_encrypted` +
#              `totp_enabled_at` + the 10 backup-code rows in a single
#              transaction. Wrong code → 422 re-render with the SAME
#              cached draft (so the QR + codes the user is staring at
#              stay valid for the retry); the cache entry is only
#              dropped on a successful confirm.
#
# Non-resumable behavior: every GET regenerates and overwrites the
# draft. A user who reloads the page sees a fresh QR + fresh codes —
# any prior unconfirmed draft is discarded.
#
# Auth: standard `Sessions::AuthConcern` (cookie session required).
# The mandatory-2FA gate allowlists `GET /settings/security/totp`
# and `POST /settings/security/totp` so the user can complete
# enrollment from the auto-opened modal on `/settings`.
class Settings::Security::TotpsController < ApplicationController
  include Sessions::TokenRotation

  # The plaintext draft (seed + 10 plaintext backup codes) lives in
  # `Rails.cache` keyed on the user id, NOT in `flash` or the session
  # cookie. Flash payloads briefly persist client-side as the Rails
  # encrypted session cookie blob; cache lives entirely server-side
  # and self-expires after 5 minutes of inactivity.
  ENROLLMENT_DRAFT_TTL = 5.minutes

  def self.enrollment_cache_key(user_id)
    "totp_enrollment_draft:#{user_id}"
  end

  # GET /settings/security/totp
  #
  # Mandatory-2FA means a configured user should never see this page;
  # if they somehow land on it (deep link), bounce them home — there
  # is no web-side disable / manage surface anymore.
  def new
    if Current.user.totp_enabled?
      redirect_to root_path, notice: t("settings.totp.flash.already_on")
      return
    end

    draft = generate_draft!
    @seed = draft[:seed]
    @codes = draft[:codes]
    @totp_uri = ROTP::TOTP.new(@seed, issuer: TotpHelper::TOTP_ISSUER)
                          .provisioning_uri(Current.user.username)
  end

  # POST /settings/security/totp
  #
  # Atomic finalization. Reads the draft from `Rails.cache`, verifies
  # the submitted 6-digit code against the cached seed, and only on
  # success persists `totp_seed_encrypted` + `totp_enabled_at` + the
  # 10 backup-code digest rows in a single transaction.
  def create
    if Current.user.totp_enabled?
      redirect_to root_path, notice: t("settings.totp.flash.already_on")
      return
    end

    cache_key = self.class.enrollment_cache_key(Current.user.id)
    draft = Rails.cache.read(cache_key)

    if draft.blank? || draft[:seed].blank?
      # Draft TTL'd or cleared — start over from the GET path.
      redirect_to settings_security_totp_path,
                  alert: t("settings.totp.flash.expired")
      return
    end

    seed = draft[:seed]
    plaintext_codes = Array(draft[:codes])
    code = params[:code].to_s.strip

    if verify_against_seed(seed, code)
      ActiveRecord::Base.transaction do
        # Clear any stale rows from a previous half-attempted enroll
        # (defense in depth — none should exist on the atomic path).
        Current.user.totp_backup_codes.destroy_all
        Current.user.update!(
          totp_seed_encrypted: seed,
          totp_enabled_at: Time.current,
          totp_disabled_at: nil,
          totp_last_used_step: nil
        )
        plaintext_codes.each do |plaintext|
          Current.user.totp_backup_codes.create!(
            code_digest: BCrypt::Password.create(plaintext)
          )
        end

        Pito::Auth::AuditLogger.call(
          acting_user: Current.user,
          source_surface: :web,
          action: :totp_enroll,
          target: Current.user,
          metadata: { enrolled_user_id: Current.user.id }
        )
      end

      # Rotate the session token after the privileged enrollment so a
      # captured pre-enrollment cookie cannot ride alongside the new
      # 2FA seed (LD-12).
      rotate_session_token!

      # Drop the cache draft now that the user has confirmed.
      Rails.cache.delete(cache_key)

      redirect_to root_path, notice: t("settings.totp.flash.enrolled")
    else
      # Wrong code → 422 re-render with the SAME draft (so the QR +
      # codes on screen stay valid for the retry). The cache entry is
      # intentionally NOT regenerated here; only fresh GETs do that.
      @seed = seed
      @codes = plaintext_codes
      @totp_uri = ROTP::TOTP.new(@seed, issuer: TotpHelper::TOTP_ISSUER)
                            .provisioning_uri(Current.user.username)
      flash.now[:alert] = t("settings.totp.flash.login_failed")
      render :new, status: :unprocessable_content
    end
  end

  private

  # Generate a fresh draft (seed + 10 plaintext backup codes) and
  # stash it in `Rails.cache`. Overwrites any prior draft for this
  # user — non-resumable enrollment per the 2026-05-16 cleanup.
  def generate_draft!
    seed = ROTP::Base32.random_base32
    codes = Array.new(Pito::Auth::TotpEnroller::BACKUP_CODE_COUNT) do
      Pito::Auth::TotpEnroller.generate_code
    end
    Rails.cache.write(
      self.class.enrollment_cache_key(Current.user.id),
      { seed: seed, codes: codes },
      expires_in: ENROLLMENT_DRAFT_TTL
    )
    { seed: seed, codes: codes }
  end

  # Stateless verify against the cached draft seed (NOT the user row,
  # which is still blank at this point). Mirrors the validation logic
  # in `Pito::Auth::TotpVerifier` minus the replay watermark — the user is
  # mid-enrollment, there is no prior watermark to defend against.
  def verify_against_seed(seed, code)
    return false if seed.blank?

    normalized = code.to_s.strip
    return false unless normalized.match?(/\A\d{6}\z/)

    totp = ROTP::TOTP.new(seed)
    !totp.verify(normalized, drift_behind: 30).nil?
  rescue StandardError => e
    Rails.logger.warn("[Settings::Security::TotpsController] verify failed: #{e.class}: #{e.message}")
    false
  end
end
