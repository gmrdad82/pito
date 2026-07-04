# frozen_string_literal: true

module Pito
  # Top banner inviting Android BROWSER visitors to install the native app.
  # Rendered from the application layout on every request; #render? narrows it
  # to Android user agents that are NOT already inside the native shell (the
  # shell marks its UA with "Hotwire Native" — the same marker
  # ApplicationController#hotwire_native_app? checks; never show an app ad
  # inside the app). Ships hidden: the pito--app-banner Stimulus controller
  # reveals it only when no localStorage dismissal is present, so dismissed
  # visitors never get a flash of banner before JS settles.
  class GetAppBannerComponent < ApplicationComponent
    # Stable asset name on the latest pito-android release — this URL never
    # changes between releases, so it is safe to bake in.
    APK_URL = "https://github.com/gmrdad82/pito-android/releases/latest/download/pito.apk"

    ANDROID_MARKER = "Android"
    NATIVE_MARKER  = "Hotwire Native"

    def initialize(user_agent:)
      @user_agent = user_agent.to_s
      super()
    end

    def render?
      android? && !native_app?
    end

    private

    def android?
      @user_agent.include?(ANDROID_MARKER)
    end

    def native_app?
      @user_agent.include?(NATIVE_MARKER)
    end
  end
end
