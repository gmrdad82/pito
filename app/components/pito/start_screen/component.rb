# frozen_string_literal: true

module Pito
  module StartScreen
    class Component < ViewComponent::Base
      # @param repo_url [String] GitHub source link — bottom-left corner.
      # @param license_url [String] License link — bottom-right corner.
      renders_one :logo

      def initialize(repo_url:, license_url:)
        @repo_url = repo_url
        @license_url = license_url
        @tip = random_tip
      end

      def random_tip
        tips = I18n.t("pito.start_screen.tip_dictionary")
        tips.sample
      end
    end
  end
end
