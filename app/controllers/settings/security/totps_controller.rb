# Phase 25 — 01e. TOTP 2FA management surface (web only).
#
# Six actions cover enrollment + disable. Backup-code regeneration is
# a sibling controller (`Settings::Security::TotpBackupCodesController`).
#
#   - `new`              — pre-enroll status + `[ enroll ]` link.
#   - `create`           — generates the seed + 10 backup codes via
#                          `Auth::TotpEnroller`, stashes the one-shot
#                          payload in the flash, redirects to `show`.
#   - `show`             — one-shot view of the QR / seed / codes plus
#                          the `[ confirm with code ]` form. If the
#                          flash is gone, redirects to `new`.
#   - `update`           — accepts a fresh 6-digit code and stamps
#                          `totp_enabled_at`. Audit-logs.
#   - `destroy_screen`   — action-screen confirmation for disable.
#                          Submit re-prompts the user for a fresh
#                          TOTP code (no JS confirm).
#   - `destroy_confirmed` — verifies the code + `confirm=yes`, then
#                           delegates to `Auth::TotpDisabler`.
#
# Auth: standard `Sessions::AuthConcern` requirement applies to every
# action. The acting user is `Current.user` — the user enrolling /
# disabling is always themselves.
class Settings::Security::TotpsController < ApplicationController
  include Sessions::TokenRotation

  # P25 follow-up — F2. The one-shot enrollment payload (seed + 10
  # plaintext backup codes) is stashed in `Rails.cache` keyed on the
  # user id — NOT in `flash`. Flash payloads briefly persist
  # client-side as the Rails encrypted session cookie blob; the seed
  # plus 10 plaintext codes is the strongest single artifact an
  # attacker could exfiltrate from a captured cookie, so we keep
  # those bytes entirely server-side and TTL them at 5 minutes.
  ONE_SHOT_CACHE_TTL = 5.minutes

  def self.enrollment_cache_key(user_id)
    "totp_enrollment_one_shot:#{user_id}"
  end

  # GET /settings/security/totp
  def new
    @totp_enabled = Current.user.totp_enabled?
    @unused_backup_codes_count = Current.user.totp_backup_codes.unused.count if @totp_enabled
  end

  # POST /settings/security/totp
  def create
    # Already-confirmed users must disable before re-enrolling.
    # Mid-enrollment users (seed present, no `enabled_at`) are allowed
    # to start over so a lost one-shot flash doesn't strand them.
    if Current.user.totp_enabled_at.present?
      redirect_to settings_security_totp_path,
                  alert: "2FA is already on. disable it first to re-enroll."
      return
    end

    result = Auth::TotpEnroller.call(user: Current.user)
    # P25 F2 — write the one-shot payload to Rails.cache (NOT flash).
    # Self-expires in 5 min; deleted explicitly on successful
    # `update` confirm.
    Rails.cache.write(
      self.class.enrollment_cache_key(Current.user.id),
      { seed: result[:seed], codes: result[:codes] },
      expires_in: ONE_SHOT_CACHE_TTL
    )
    redirect_to settings_security_totp_show_path
  rescue Auth::TotpEnroller::AlreadyEnrolled
    redirect_to settings_security_totp_path,
                alert: "2FA is already on. disable it first to re-enroll."
  end

  # GET /settings/security/totp/show
  def show
    # P25 F2 — read the one-shot payload from Rails.cache. The cache
    # entry survives across multiple GETs within the 5-minute TTL
    # (we do NOT delete on read here — we only delete on `update`
    # success). That preserves the same "wrong-code 422 re-renders
    # the QR + codes" behavior the flash.keep call used to provide,
    # WITHOUT leaving the plaintext payload in the user's cookie.
    cache_key = self.class.enrollment_cache_key(Current.user.id)
    payload = Rails.cache.read(cache_key)

    if payload.blank? || payload[:seed].blank?
      redirect_to settings_security_totp_path,
                  alert: "enrollment expired. start again."
      return
    end

    @seed   = payload[:seed]
    @codes  = Array(payload[:codes])
    @totp_uri = ROTP::TOTP.new(@seed, issuer: TotpHelper::TOTP_ISSUER)
                          .provisioning_uri(Current.user.email)
  end

  # PATCH /settings/security/totp/confirm
  def update
    # The seed of record is on `Current.user.totp_seed_encrypted` —
    # `Auth::TotpEnroller` persisted it during `create`. The flash
    # one-shot payload is for re-rendering the QR + codes on a 422;
    # it is NOT load-bearing for verification.
    seed = Current.user.totp_seed_encrypted
    if seed.blank?
      redirect_to settings_security_totp_path,
                  alert: "enrollment expired. start again."
      return
    end

    code = params[:code].to_s.strip

    if Auth::TotpVerifier.call(user: Current.user, code: code) == :ok
      Current.user.update!(totp_enabled_at: Time.current, totp_disabled_at: nil)
      Auth::AuditLogger.call(
        acting_user: Current.user,
        source_surface: :web,
        action: :totp_enroll,
        target: Current.user,
        metadata: { enrolled_user_id: Current.user.id }
      )
      # Phase 25 — 01g (LD-12 extension). Rotate the session token
      # after the privileged enrollment so a captured pre-enrollment
      # cookie cannot ride alongside the new 2FA seed.
      rotate_session_token!
      # P25 F2 — drop the one-shot payload from cache now that the
      # user has confirmed. The seed lives on `totp_seed_encrypted`
      # going forward; the codes never need to be redisplayed.
      Rails.cache.delete(self.class.enrollment_cache_key(Current.user.id))
      redirect_to settings_security_totp_path, notice: "2FA enrolled."
    else
      # P25 F2 — re-read the cache for the wrong-code 422 re-render
      # so the QR / codes block still appears. The cache entry has
      # NOT been deleted (we only delete on confirm success), so
      # within the 5-min TTL the user can retry without losing the
      # display.
      cache_key = self.class.enrollment_cache_key(Current.user.id)
      payload = Rails.cache.read(cache_key) || {}
      @seed = seed
      @codes = Array(payload[:codes])
      @totp_uri = ROTP::TOTP.new(@seed, issuer: TotpHelper::TOTP_ISSUER)
                            .provisioning_uri(Current.user.email)
      flash.now[:alert] = "login failed."
      render :show, status: :unprocessable_content
    end
  end

  # GET /settings/security/totp/disable
  def destroy_screen
    unless Current.user.totp_enabled?
      redirect_to settings_security_totp_path,
                  alert: "2FA is already off."
      nil
    end
  end

  # POST /settings/security/totp/disable
  #
  # Defense-in-depth gate. Disabling 2FA is a high-impact action — it
  # strips the seed AND every backup code. We ask for BOTH the current
  # password and a fresh TOTP code, so a captured authenticated cookie
  # alone cannot turn 2FA off. Failure copy is intentionally generic —
  # the response must not leak whether the password or the code was
  # the failing field.
  def destroy_confirmed
    unless Current.user.totp_enabled?
      redirect_to settings_security_totp_path,
                  alert: "2FA is already off."
      return
    end

    password = params[:password].to_s
    code     = params[:code].to_s.strip
    confirm  = params[:confirm].to_s

    if confirm != "yes"
      redirect_to settings_security_totp_path,
                  alert: "disable cancelled."
      return
    end

    password_ok = password.present? && Current.user.authenticate(password)
    code_ok     = Auth::TotpVerifier.call(user: Current.user, code: code) == :ok

    unless password_ok && code_ok
      flash.now[:alert] = "credentials don't match."
      render :destroy_screen, status: :unprocessable_content
      return
    end

    Auth::TotpDisabler.call(user: Current.user,
                            acting_user: Current.user,
                            source_surface: :web)
    # Phase 25 — 01g (LD-12 extension). Rotate the session token
    # on disable so a captured cookie can't survive across the
    # 2FA-off transition.
    rotate_session_token!
    redirect_to settings_security_totp_path, notice: "2FA disabled."
  end
end
