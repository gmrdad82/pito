# frozen_string_literal: true

module Pito
  module Channel
    # The TINY (35px) round channel avatar for list-table cells — the
    # `list channels` Avatar column. Renders the locally-cached `:xs` variant
    # (70px master → 35px CSS, 2× for hiDPI) with the same theme-contrast ring
    # the score-card avatars wear (1px solid var(--border-faded) — the show-game
    # recommendation-column ring; see
    # `.pito-channel-tiny-avatar`); a missing avatar falls back to the shared
    # click-to-sync placeholder circle, sized by the same class.
    #
    # Rendered via #call (no template) — a single ImageRender delegation.
    class TinyAvatarComponent < ViewComponent::Base
      def initialize(channel:)
        @channel = channel
      end

      def call
        render Pito::ImageRender.call(
          url:            @channel.avatar_xs_url,
          shape:          :circle,
          sync_command:   "sync channel #{@channel.at_handle}",
          alt:            @channel.title.to_s,
          html_class:     "pito-channel-tiny-avatar block",
          fallback_class: "pito-channel-tiny-avatar"
        )
      end
    end
  end
end
