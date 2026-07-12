# frozen_string_literal: true

module Pito
  # Decides how ONE entity image renders: the image itself when its (host-less
  # proxy) url is present, else a click-to-sync placeholder
  # (Pito::ImageFallbackComponent). This keeps the url / placeholder branch — and
  # the placeholder markup — out of every template. Callers pass the url from
  # their existing variant helper (which returns nil when nothing is attached),
  # so the per-entity variant logic stays where it already lives:
  #
  #   <%= render Pito::ImageRender.call(
  #         url:          detail_cover_url,          # nil when no cover art
  #         shape:        :rect,
  #         sync_command: "sync game ##{game.id}",
  #         alt:          game.title,
  #         html_class:   "block pito-cover-pan"
  #       ) %>
  #
  # Returns a RENDERABLE (responds to #render_in) in BOTH branches so the call
  # site never has to know which one it got — `render(...)` handles either.
  class ImageRender
    # @param url          [String, nil] the resolved (host-less) image path; nil → placeholder
    # @param shape        [Symbol] :rect (banner/thumbnail/cover) | :circle (avatar) — placeholder only
    # @param sync_command [String] the chat command the placeholder click prefills + submits
    # @param alt          [String, nil] <img> alt text
    # @param html_class   [String, nil] <img> class attribute (image branch)
    # @param fallback_class [String, nil] host SIZING class for the placeholder so
    #   it occupies the same box the image would (usually the image's sizing class)
    # @return [ImageTag, Pito::ImageFallbackComponent] a renderable
    def self.call(url:, shape:, sync_command:, alt: nil, html_class: nil, fallback_class: nil)
      if url.present?
        ImageTag.new(url: url, alt: alt, html_class: html_class)
      else
        Pito::ImageFallbackComponent.new(shape: shape, sync_command: sync_command, extra_class: fallback_class)
      end
    end

    # Minimal renderable wrapping `image_tag` so both branches share one call-site
    # shape. `image_tag` is a standalone helper (needs no view context), so
    # #render_in ignores its argument.
    class ImageTag
      def initialize(url:, alt: nil, html_class: nil)
        @url        = url
        @alt        = alt.to_s
        @html_class = html_class
      end

      def render_in(_view_context = nil, &_block)
        ActionController::Base.helpers.image_tag(@url, alt: @alt, class: @html_class)
      end
    end
  end
end
