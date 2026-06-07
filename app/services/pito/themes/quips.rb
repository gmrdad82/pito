# frozen_string_literal: true

module Pito
  module Themes
    # Sampler for witty apply-confirmation quips.
    #
    # Delegates to Pito::Copy.render — the single copy engine seam.
    # Copy lives at pito.copy.theme.applied (i18n array, each entry interpolates
    # %{theme} with the theme label).
    #
    # @deprecated Callers should migrate to Pito::Copy.render("pito.copy.theme.applied", theme: label)
    #   directly. This module is kept as a thin wrapper to avoid a large diff while
    #   existing callers are updated.
    module Quips
      # Return one interpolated quip string for the given theme label.
      #
      # @param label [String] the theme's display label (e.g. "Dracula")
      # @return [String]
      def self.applied(label)
        Pito::Copy.render("pito.copy.theme.applied", { theme: label })
      end
    end
  end
end
