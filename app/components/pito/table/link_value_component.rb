# frozen_string_literal: true

module Pito
  module Table
    # Renders an external link for use as a `value_component:` in
    # Pito::Table::KeyValueRowComponent. Displays the URL without the scheme
    # (e.g. "youtube.com/@handle") while href carries the full URL.
    #
    # Usage:
    #   render(Pito::Table::KeyValueRowComponent.new(
    #     key_text:        "YouTube Channel",
    #     value_component: Pito::Table::LinkValueComponent.new(url: channel.youtube_channel_url)
    #   ))
    class LinkValueComponent < ViewComponent::Base
      # Yellow text with the diagonal yellow→orange shimmer sweep (same as the
      # keyboard-shortcut tokens). A per-url stagger offset keeps the two channel
      # links out of phase.
      DEFAULT_CLASS = "text-yellow pito-kbd-shimmer"

      def initialize(url:, css_class: DEFAULT_CLASS)
        @url       = url
        @css_class = css_class
      end

      def call
        tag.a(display_text, href: @url, target: "_blank", rel: "noopener",
              class: "#{@css_class} #{Pito::Shimmer.offset_class(@url.to_s)}".strip)
      end

      private

      def display_text
        @url.sub(%r{\Ahttps?://(?:www\.)?}, "")
      end
    end
  end
end
