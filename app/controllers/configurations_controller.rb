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
  #
  # Kept byte-for-byte aligned with the shell's BUNDLED fallback config
  # (pito-android v1.0.0): the app fetches this on every launch and
  # disk-caches it OVER its bundled copy, so any divergence here silently
  # overrides the shell's intended behavior. pull_to_refresh stays OFF —
  # the scrollback is a live cable stream, and the gesture fights scrolling.
  ANDROID_V1_CONFIG = {
    settings: {},
    rules: [
      {
        patterns: [ ".*" ],
        properties: {
          context:                 "default",
          uri:                     "hotwire://fragment/web",
          fallback_uri:            "hotwire://fragment/web",
          pull_to_refresh_enabled: false
        }
      },
      {
        patterns: [ "^$", "^/$" ],
        properties: { presentation: "clear_all" }
      }
    ]
  }.freeze

  def android_v1
    expires_in 1.hour, public: true
    render json: ANDROID_V1_CONFIG
  end
end
