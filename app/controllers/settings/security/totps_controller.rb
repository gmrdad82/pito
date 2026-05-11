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
  FLASH_KEY = :totp_enrollment_one_shot

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
    flash[FLASH_KEY] = {
      "seed" => result[:seed],
      "codes" => result[:codes]
    }
    redirect_to settings_security_totp_show_path
  rescue Auth::TotpEnroller::AlreadyEnrolled
    redirect_to settings_security_totp_path,
                alert: "2FA is already on. disable it first to re-enroll."
  end

  # GET /settings/security/totp/show
  def show
    payload = flash[FLASH_KEY]
    if payload.blank? || payload["seed"].blank?
      redirect_to settings_security_totp_path,
                  alert: "enrollment expired. start again."
      return
    end

    @seed   = payload["seed"]
    @codes  = Array(payload["codes"])
    @totp_uri = ROTP::TOTP.new(@seed, issuer: TotpHelper::TOTP_ISSUER)
                          .provisioning_uri(Current.user.email)

    # Keep the one-shot payload alive across the confirm submit so a
    # wrong-code 422 re-renders the QR + codes (the user needs the QR
    # if they didn't scan it yet). `flash.keep` survives the render
    # cycle for one more request.
    flash.keep(FLASH_KEY)
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
      flash.delete(FLASH_KEY)
      redirect_to settings_security_totp_path, notice: "2FA enrolled."
    else
      payload = flash[FLASH_KEY] || {}
      @seed = seed
      @codes = Array(payload["codes"])
      @totp_uri = ROTP::TOTP.new(@seed, issuer: TotpHelper::TOTP_ISSUER)
                            .provisioning_uri(Current.user.email)
      flash.keep(FLASH_KEY)
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
  def destroy_confirmed
    unless Current.user.totp_enabled?
      redirect_to settings_security_totp_path,
                  alert: "2FA is already off."
      return
    end

    code = params[:code].to_s.strip
    confirm = params[:confirm].to_s

    if confirm != "yes"
      redirect_to settings_security_totp_path,
                  alert: "disable cancelled."
      return
    end

    if Auth::TotpVerifier.call(user: Current.user, code: code) == :ok
      Auth::TotpDisabler.call(user: Current.user,
                              acting_user: Current.user,
                              source_surface: :web)
      redirect_to settings_security_totp_path, notice: "2FA disabled."
    else
      flash.now[:alert] = "login failed."
      render :destroy_screen, status: :unprocessable_content
    end
  end
end
