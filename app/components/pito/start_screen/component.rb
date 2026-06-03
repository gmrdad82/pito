# frozen_string_literal: true

module Pito
  module StartScreen
    class Component < ViewComponent::Base
      attr_reader :repo_url, :license_url, :tip, :badge_class, :badge_text, :exclamation_class

      def initialize(repo_url:, license_url:,
                     tips_key: "pito.start_screen.tips",
                     badge_text: nil,
                     badge_text_key: "pito.start_screen.tip_prefix",
                     badge_class: "font-bold text-yellow",
                     exclamation_class: "text-orange")
        @repo_url          = repo_url
        @license_url       = license_url
        @badge_text        = badge_text || I18n.t(badge_text_key)
        @badge_class       = badge_class
        @exclamation_class = exclamation_class
        @tip               = I18n.t(tips_key).sample
      end
    end
  end
end
