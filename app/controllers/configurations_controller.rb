# frozen_string_literal: true

# ConfigurationsController — serves machine-readable configuration documents
# for native clients. All actions are public (no authentication required).
class ConfigurationsController < ApplicationController
  # This endpoint is consumed by the Android Hotwire Native client before it
  # has any session; skip the auth gate.
  allow_anonymous :android_v1

  # Minimal v1 path-configuration document for the Hotwire Native Android
  # client. All routes are treated as web screens at this stage — no native
  # fragments have been promoted yet.
  ANDROID_V1_CONFIG = {
    settings: {},
    rules: [
      {
        patterns: [ ".*" ],
        properties: {
          context:                "default",
          uri:                   "hotwire://fragment/web",
          pull_to_refresh_enabled: true
        }
      }
    ]
  }.freeze

  def android_v1
    render json: ANDROID_V1_CONFIG
  end
end
