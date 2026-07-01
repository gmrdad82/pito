# frozen_string_literal: true

module Pito
  # A missing-image placeholder: a fg-muted shape (rectangle for a banner /
  # thumbnail / cover, circle for an avatar) that FILLS its host box and — when
  # the box is big enough (a CSS container-query hides it on small avatars) —
  # shows a centered "No image." line + a "sync" affordance in the background
  # token for max contrast against the muted fill.
  #
  # The WHOLE box is click-to-sync: it reuses pito--chat-prefill to prefill
  # `sync_command` and dispatch a REAL Enter keydown — the same mechanism as the
  # `#id` "show" click on identifier tokens (Pito::Shimmer::TokenComponent).
  #
  # Rendered via Pito::ImageRender (which returns it when nothing is attached);
  # call sites don't instantiate it directly.
  class ImageFallbackComponent < ViewComponent::Base
    SHAPES = %i[rect circle].freeze

    # @param shape        [Symbol] :rect | :circle (unknown → :rect)
    # @param sync_command [String] the chat command the click prefills + submits
    # @param extra_class  [String, nil] the host SIZING class (the same class the
    #   image would carry — e.g. "pito-channel-item__avatar"), so the placeholder
    #   occupies the exact box the image would. Mirrors the `--placeholder` pattern.
    def initialize(shape:, sync_command:, extra_class: nil)
      @shape        = SHAPES.include?(shape) ? shape : :rect
      @sync_command = sync_command.to_s
      @extra_class  = extra_class.presence
    end

    def call
      tag.div(class: css_classes, **prefill_attrs) do
        tag.div(class: "pito-image-fallback__copy") do
          safe_join([
            tag.span(no_image_copy, class: "pito-image-fallback__label"),
            tag.span(sync_label, class: "pito-image-fallback__sync")
          ])
        end
      end
    end

    private

    def css_classes
      [
        "pito-image-fallback",
        ("pito-image-fallback--circle" if @shape == :circle),
        @extra_class
      ].compact.join(" ")
    end

    # The whole box carries the shared chat-prefill data (submit: true → real
    # Enter). `role`/`tabindex` make it a keyboard-reachable button.
    def prefill_attrs
      {
        role:     "button",
        tabindex: "0",
        data:     Pito::Shimmer::TokenComponent.prefill_data(@sync_command, submit: true)
      }
    end

    def no_image_copy
      Pito::Copy.render("pito.copy.images.no_image")
    end

    def sync_label
      Pito::Copy.render("pito.copy.images.sync_cta")
    end
  end
end
