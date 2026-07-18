# frozen_string_literal: true

# POST /device_tokens — the Android shell registers (or refreshes) its FCM
# device token so a later push-sender phase has somewhere to deliver to.
# Pure plumbing: no broadcaster calls, no scrollback event — registering a
# token never touches the chat the owner sees.
#
# Auth gating: inherits Sessions::AuthConcern from ApplicationController.
# No allow_anonymous — unauthenticated requests get an explicit 401 (JSON;
# this endpoint has no browser form, so there's no HTML branch to redirect).
class DeviceTokensController < ApplicationController
  # Upserts by token: a re-registration (app relaunch with the same FCM
  # token, or just a periodic keepalive) finds the existing row and bumps
  # last_seen_at instead of creating a duplicate — the unique index on
  # token backs this up at the DB level. A missing/blank token never reaches
  # the DB: find_or_initialize_by(token: nil/"") always initializes a new,
  # unsaved record, and the model's presence validation rejects it.
  def create
    device_token = DeviceToken.find_or_initialize_by(token: device_token_params[:token])
    device_token.platform = device_token_params[:platform] if device_token_params[:platform].present?
    device_token.last_seen_at = Time.current

    if device_token.save
      head :no_content
    else
      render json: { errors: device_token.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def device_token_params
    params.permit(:token, :platform)
  end
end
