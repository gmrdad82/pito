# frozen_string_literal: true

module Pito
  module Lists
    # Generic, domain-agnostic footer builder for list surfaces (E7 contract).
    #
    # Produces a one-or-two-line String (or nil) describing the column and sort
    # options available on a given list surface. Callers supply DERIVED data —
    # what is addable, removable, and sortable — rather than domain objects,
    # which keeps this builder surface-agnostic.
    #
    # == Per-surface option derivation
    #
    # Figuring out which columns are addable (available minus visible) or
    # removable (currently visible extras), and which sort keys the surface
    # supports, is the CALLER's responsibility. Each surface's own ListColumns
    # module knows its COLUMNS/SORT_KEYS constants and the currently-selected
    # column set; this builder only renders what it is told.
    #
    # == Copy keys used
    #
    #   pito.copy.list_footer.columns  — vars: %{addable}, %{removable}
    #   pito.copy.list_footer.sort     — var:  %{keys}
    #
    # Both are 1-or-50 dictionaries rendered via Pito::Copy.render.
    #
    # == Nil contract
    #
    # Returns nil when both addable AND removable are empty AND sort_keys is
    # empty — i.e., there is literally nothing to tell the user. Surfaces must
    # guard on nil before inserting the footer into the payload.
    module OptionsFooter
      module_function

      # Builds a footer string describing the surface's real options.
      #
      # @param addable   [Array<String>] column names that `with` can add
      #                  (available columns minus currently visible ones).
      #                  Pass [] when no columns can be added.
      # @param removable [Array<String>] column names that `without` can drop
      #                  (currently visible non-default columns).
      #                  Pass [] when no columns can be removed.
      # @param sort_keys [Array<String>] sortable key tokens for this surface.
      #                  Pass [] when sorting is not supported or no keys exist.
      # @return [String, nil] html-safe-safe plain String, or nil when there is
      #                       nothing to display (all inputs are empty).
      def call(addable:, removable:, sort_keys:)
        lines = []

        unless addable.empty? && removable.empty?
          # One side may be empty (e.g. every optional column already added) —
          # the dictionaries assume both vars read as lists, so an empty side
          # renders as the literal "nothing" rather than a dangling gap.
          lines << Pito::Copy.render(
            "pito.copy.list_footer.columns",
            addable:   addable.join(", ").presence || "nothing",
            removable: removable.join(", ").presence || "nothing"
          )
        end

        unless sort_keys.empty?
          lines << Pito::Copy.render(
            "pito.copy.list_footer.sort",
            keys: sort_keys.join(", ")
          )
        end

        return nil if lines.empty?

        lines.join(" ")
      end
    end
  end
end
