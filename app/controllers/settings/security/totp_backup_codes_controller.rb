# Phase 25 — 01e. Backup code management surface.
#
# Three actions:
#
#   - `show`   — count of unused codes + last-used timestamp.
#                Plaintexts are NEVER re-displayed.
#   - `new`    — action-screen confirmation. Submit invokes `create`.
#                Re-asks for a fresh TOTP code + current password to
#                authorize the rotation (the form posts `confirm=yes`
#                + `code`).
#   - `create` — verifies the fresh code, calls
#                `Auth::BackupCodeRegenerator`, displays the new codes
#                ONCE on a one-shot view.
class Settings::Security::TotpBackupCodesController < ApplicationController
  include Sessions::TokenRotation

  FLASH_KEY = :totp_backup_codes_one_shot

  # GET /settings/security/totp_backup_codes
  def show
    unless Current.user.totp_enabled?
      redirect_to settings_security_totp_path,
                  alert: "enable 2FA first to manage backup codes."
      return
    end

    @unused_count = Current.user.totp_backup_codes.unused.count
    @used_count   = Current.user.totp_backup_codes.used.count
    @last_used_at = Current.user.totp_backup_codes.used.maximum(:used_at)

    payload = flash[FLASH_KEY]
    if payload.present?
      @one_shot_codes = Array(payload["codes"])
      flash.delete(FLASH_KEY)
    end
  end

  # GET /settings/security/totp_backup_codes/new
  def new
    unless Current.user.totp_enabled?
      redirect_to settings_security_totp_path,
                  alert: "enable 2FA first to manage backup codes."
      nil
    end
  end

  # POST /settings/security/totp_backup_codes
  #
  # Defense-in-depth gate. Regenerating backup codes invalidates every
  # existing unused code; we ask for BOTH the current password and a
  # fresh TOTP code so a captured authenticated cookie cannot rotate
  # the recovery channel out from under the user. Failure copy is
  # intentionally generic — the response must not leak whether the
  # password or the code was the failing field.
  def create
    unless Current.user.totp_enabled?
      redirect_to settings_security_totp_path,
                  alert: "enable 2FA first to manage backup codes."
      return
    end

    confirm  = params[:confirm].to_s
    password = params[:password].to_s
    code     = params[:code].to_s.strip

    if confirm != "yes"
      redirect_to settings_security_totp_backup_codes_path,
                  alert: "regenerate cancelled."
      return
    end

    password_ok = password.present? && Current.user.authenticate(password)
    code_ok     = Auth::TotpVerifier.call(user: Current.user, code: code) == :ok

    unless password_ok && code_ok
      flash.now[:alert] = "credentials don't match."
      render :new, status: :unprocessable_content
      return
    end

    codes = Auth::BackupCodeRegenerator.call(
      user: Current.user,
      acting_user: Current.user,
      source_surface: :web
    )
    # Phase 25 — 01g (LD-12 extension). Rotate the session token on
    # regenerate so a captured cookie can't ride alongside fresh
    # backup codes.
    rotate_session_token!
    flash[FLASH_KEY] = { "codes" => codes }
    redirect_to settings_security_totp_backup_codes_path,
                notice: "backup codes regenerated."
  rescue Auth::BackupCodeRegenerator::NotEnrolled
    redirect_to settings_security_totp_path,
                alert: "enable 2FA first to manage backup codes."
  end
end
