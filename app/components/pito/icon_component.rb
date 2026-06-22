# frozen_string_literal: true

require "cgi"

module Pito
  # Renders a vendored Lucide outline icon as an inline SVG.
  # The icon inherits surrounding text colour via `currentColor` and
  # scales to 1em × 1em — never larger than the 14px base font.
  #
  # API:
  #   Pito::IconComponent.new(name: "thumbs-up", label: "likes")  # labelled
  #   Pito::IconComponent.new(name: "thumbs-up")                  # decorative
  #
  # Icons are vendored as Lucide outline SVGs in public/icons/<name>.svg
  # (viewBox 0 0 24 24, fill none, stroke currentColor, stroke-width 1.5).
  # The component inlines the SVG markup so `currentColor` resolves to
  # the surrounding text colour in every theme.
  #
  # Raises ArgumentError when the named icon file does not exist.
  class IconComponent < ViewComponent::Base
    ICON_DIR = Rails.root.join("public/icons").freeze

    # @param name  [String]      icon filename without .svg extension
    # @param label [String, nil] accessible label; nil renders as aria-hidden
    def initialize(name:, label: nil)
      @name  = name.to_s
      @label = label.to_s.presence
    end

    def call
      raw = self.class.svg_cache[@name]

      a11y = if @label
        %( role="img" aria-label="#{CGI.escapeHTML(@label)}")
      else
        %( aria-hidden="true")
      end

      # Inject class, sizing, and accessibility attrs into the opening <svg tag.
      # The vendored files carry no width/height so there is nothing to strip.
      raw
        .sub("<svg", %(<svg class="pito-icon" width="1em" height="1em"#{a11y}))
        .html_safe
    end

    # Class-level cache: each named icon is read from disk once per process.
    # The default block raises ArgumentError immediately on an unknown name,
    # before storing anything, so bad lookups are never memoised.
    def self.svg_cache
      @svg_cache ||= Hash.new { |h, name| h[name] = load_svg(name) }
    end

    def self.load_svg(name)
      path = ICON_DIR.join("#{name}.svg")
      raise ArgumentError, "pito-icon: unknown icon #{name.inspect} — no file at #{path}" unless path.exist?

      path.read
    end
  end
end
