# frozen_string_literal: true

module Pito
  # Builds a HOST-LESS ActiveStorage proxy path for an attachment — or one of
  # its variants — so the browser resolves the image against whatever host is
  # serving the page (plain localhost, an off-box tunnel, production). No scheme
  # or host is ever emitted; the path always starts with "/rails/active_storage".
  #
  # Returns nil when nothing is attached (or the variant can't be built) so
  # callers fall back to their placeholder.
  #
  #   Pito::ImagePath.call(game.cover_art, variant: ::Game::COVER_VARIANT)
  #   Pito::ImagePath.call(channel.avatar, variant: { resize_to_limit: [240, 240] })
  #   Pito::ImagePath.call(video.thumbnail)            # plain attachment, no variant
  class ImagePath
    include Rails.application.routes.url_helpers

    # @param attachment [ActiveStorage::Attached::One, nil] a `has_one_attached`
    #   proxy (cover_art / thumbnail / avatar).
    # @param variant [Hash, Symbol, nil] transformations passed to `#variant`;
    #   nil renders the original attachment.
    def self.call(attachment, variant: nil)
      new(attachment, variant: variant).call
    end

    def initialize(attachment, variant: nil)
      @attachment = attachment
      @variant    = variant
    end

    def call
      return nil unless @attachment.respond_to?(:attached?) && @attachment.attached?

      # `rails_storage_proxy_path` routes both blobs/attachments and variants to
      # the proxy controller. `only_path: true` forces a host-less path even when
      # no default_url_options[:host] is configured — so the image always
      # resolves against whatever host serves the page.
      rails_storage_proxy_path(representation, only_path: true)
    rescue StandardError
      nil
    end

    private

    def representation
      @variant ? @attachment.variant(@variant) : @attachment
    end
  end
end
