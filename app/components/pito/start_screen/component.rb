# frozen_string_literal: true

module Pito
  module StartScreen
    class Component < ViewComponent::Base
      attr_reader :repo_url, :license_url, :tip, :badge_class, :badge_text, :exclamation_class, :channels

      def initialize(repo_url:, license_url:,
                     tips_key: "pito.copy.start_screen.tips",
                     badge_text: nil,
                     badge_text_key: "pito.start_screen.tip_prefix",
                     badge_class: "font-bold text-yellow",
                     exclamation_class: "text-orange",
                     channels: [])
        @repo_url          = repo_url
        @license_url       = license_url
        @badge_text        = badge_text || I18n.t(badge_text_key)
        @badge_class       = badge_class
        @exclamation_class = exclamation_class
        @tip               = Pito::Copy.render(tips_key)
        # Coerce nil → [] (the keyword default only applies when the arg is
        # omitted, not when a caller passes an explicit nil — e.g. the not_found
        # path renders with `channels: @channels` before any before_action has
        # loaded `@channels`). Guards `@channels.any?` in the template.
        @channels          = channels || []
      end
    end
  end
end
