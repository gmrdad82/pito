# frozen_string_literal: true

module Pito
  module Sidebar
    class SectionComponent < ViewComponent::Base
      renders_one :body

      # @param title_key [String] i18n key for the section label.
      def initialize(title_key:)
        @title_key = title_key
      end
    end
  end
end
