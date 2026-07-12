# frozen_string_literal: true

module Pito
  # Generic SHINY material chip — the reusable surface behind the stones/awards
  # design system (`.pito-shiny` in application.css: material fill, travelling
  # gleam, breathing halo). Domain-agnostic on purpose: the achievement
  # BadgeComponent owns badge semantics (thresholds, metrics, labels); anything
  # else that wants the shiny LOOK (the get-the-app banner) composes this chip
  # with pure kwargs and a content block.
  #
  #   render(Pito::ShinyChipComponent.new(material: "gold", extra_class: "pito-get-app")) do
  #     …content…
  #   end
  #
  # kwargs:
  #   material:    (String) one of the .pito-shiny data-material palettes
  #                (wood/stone/amber/coral/jade/pearl/ruby/opal/silver/gold/diamond).
  #   tag_name:    (:span | :div) — :span for inline chips, :div for banners.
  #   extra_class: (String, nil) — modifier classes layered over .pito-shiny.
  #   seed:        (String) — gleam-stagger seed so adjacent chips never sync.
  class ShinyChipComponent < ViewComponent::Base
    IRIDESCENT = %w[pearl opal diamond].freeze

    def initialize(material:, tag_name: :span, extra_class: nil, seed: nil)
      @material    = material.to_s
      @tag_name    = tag_name
      @extra_class = extra_class
      @seed        = seed || @material
    end

    def call
      tag.public_send(@tag_name, class: css_classes, data: { material: @material }) do
        content
      end
    end

    private

    # The shinies-specific 20-bucket stagger (mirrors BadgeComponent#offset_class).
    def offset_class
      "pito-shiny-s#{@seed.sum % 20}"
    end

    def css_classes
      base = "pito-shiny #{offset_class}"
      base += " pito-shiny--iridescent" if IRIDESCENT.include?(@material)
      base += " pito-shiny--award" if Pito::Achievement::Tier::AWARDS.value?(@material)
      [ base, @extra_class ].compact.join(" ")
    end
  end
end
