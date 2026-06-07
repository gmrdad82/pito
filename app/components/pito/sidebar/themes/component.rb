# frozen_string_literal: true

module Pito
  module Sidebar
    module Themes
      # Renders the theme picker list for the sidebar.
      #
      # Displays two sections — Dark and Light — each headed by a
      # `Pito::Section::SectionHeaderComponent` (orange, consistent with the
      # conversations sidebar). Each row carries the `.pito-theme-row` hook,
      # `data-theme-name`, an `is-current` class on the active theme, and a
      # ● bullet marker for quick visual identification.
      #
      # The outer list container mounts `data-controller="pito--theme-nav"` so
      # P9 (`theme_nav_controller.js`) can attach keyboard navigation without any
      # additional markup changes.
      #
      # Constructor:
      #   groups        — Hash with :dark and :light arrays of
      #                   `Pito::Themes::Definition` instances, as returned by
      #                   `Pito::Themes::Registry.grouped`.
      #   current_theme — String slug of the currently active theme (from
      #                   `AppSetting.theme`).
      class Component < ViewComponent::Base
        def initialize(groups:, current_theme:)
          @dark          = groups.fetch(:dark,  [])
          @light         = groups.fetch(:light, [])
          @current_theme = current_theme
        end

        def current?(definition)
          definition.slug == @current_theme
        end

        attr_reader :dark, :light
      end
    end
  end
end
