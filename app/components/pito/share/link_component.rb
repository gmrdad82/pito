# frozen_string_literal: true

module Pito
  module Share
    # Renders the `share` confirmation message: the witty "here's your link" line
    # (pito.copy.share.shared_url, 50 variants) with the URL as a CLICKABLE link —
    # an <a target="_blank"> carrying the action shimmer class (like every other
    # clickable link/token) — plus a footage-snippet-style COPY affordance
    # (pito--clipboard) so the full link is one click to copy.
    #
    # Rendered into an html: true payload by Pito::MessageBuilder::Share::Link, so
    # the sampled sentence is frozen at creation. A leading data-pito-ts-slot keeps
    # the message's inline "HH:MM ·" timestamp on the first line.
    class LinkComponent < ViewComponent::Base
      def initialize(url:)
        @url = url.to_s
      end

      attr_reader :url

      # The witty line with %{url} interpolated as the clickable action-class link.
      # interpolate_html leaves html_safe values raw, so the <a> renders as-is.
      def sentence
        Pito::Copy.render_html("pito.copy.share.shared_url", { url: link_html })
      end

      def copy_label = I18n.t("pito.copy.share.copy_label")
      def aria_label = I18n.t("pito.copy.share.aria_label")

      private

      # Full URL as a clickable <a target="_blank"> with the action shimmer class
      # (a per-url stagger offset keeps repeated links out of phase).
      def link_html
        tag.a(url, href: url, target: "_blank", rel: "noopener",
              class: "pito-action-shimmer #{Pito::Shimmer.offset_class(url)}".strip)
      end
    end
  end
end
