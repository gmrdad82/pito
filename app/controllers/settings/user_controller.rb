# Phase 12 — user account self-service.
#
# Lets the authenticated user change their own email or password. The
# `current_password` field re-prompts the user as a confirmation gate
# before any mutation lands — standard "re-auth before sensitive
# change" pattern. There is intentionally NO account-delete, NO
# create-new-user, NO password-recovery flow on this surface. Recovery
# is deferred; see `docs/plans/beta/12-auth-ui-multi-user-readiness/`.
#
# The form re-renders with `:unprocessable_content` (422) on any
# validation or authorization failure so the existing flash + form
# error rendering pipeline works the same way as elsewhere in the app.
# Successful update redirects back to `/settings` with a flash notice.
class Settings::UserController < ApplicationController
  def show
    @user = Current.user
  end

  def update
    @user = Current.user

    current_password = params.dig(:user, :current_password).to_s
    if current_password.blank? || !@user.authenticate(current_password)
      @user.errors.add(:current_password, "is incorrect.")
      render :show, status: :unprocessable_content
      return
    end

    new_email = params.dig(:user, :email).to_s.strip
    new_password = params.dig(:user, :password).to_s
    new_password_confirmation = params.dig(:user, :password_confirmation).to_s

    attrs = {}
    attrs[:email] = new_email if new_email.present? && new_email != @user.email

    if new_password.present?
      if new_password != new_password_confirmation
        @user.errors.add(:password_confirmation, "does not match.")
        render :show, status: :unprocessable_content
        return
      end
      attrs[:password] = new_password
      attrs[:password_confirmation] = new_password_confirmation
    end

    if attrs.empty?
      redirect_to settings_path, notice: "no changes."
      return
    end

    if @user.update(attrs)
      redirect_to settings_path, notice: "account updated."
    else
      render :show, status: :unprocessable_content
    end
  end
end
