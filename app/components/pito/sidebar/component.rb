# frozen_string_literal: true

module Pito
  module Sidebar
    class Component < ViewComponent::Base
      renders_one :body
      # Optional rich subtitle (e.g. a keyboard-shortcut hint). When given it
      # takes precedence over `subtitle_key`.
      renders_one :subtitle

      # @param title [String] the entity title (e.g. "Hollow Knight").
      # @param subtitle_key [String, nil] i18n key for a plain-text subtitle line.
      # @param subtitle_args [Hash] interpolation args for the subtitle.
      def initialize(title:, subtitle_key: nil, subtitle_args: {})
        @title = title
        @subtitle_key = subtitle_key
        @subtitle_args = subtitle_args
      end
    end
  end
end
