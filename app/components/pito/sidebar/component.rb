# frozen_string_literal: true

module Pito
  module Sidebar
    class Component < ViewComponent::Base
      renders_one :body

      # @param title [String] the entity title (e.g. "Hollow Knight").
      # @param subtitle_key [String] i18n key for the subtitle line.
      # @param subtitle_args [Hash] interpolation args for the subtitle.
      def initialize(title:, subtitle_key:, subtitle_args: {})
        @title = title
        @subtitle_key = subtitle_key
        @subtitle_args = subtitle_args
      end
    end
  end
end
