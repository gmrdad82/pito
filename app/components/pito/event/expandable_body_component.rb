# frozen_string_literal: true

module Pito
  module Event
    # Unified expandable body: either a plain body span or a pito--expand block
    # with ctrl+| hint, optional expand_lines, and collapsible detail.
    #
    # Params:
    #   body            — the primary text (String|nil)
    #   expand_lines    — extra lines shown above the hint inside the expand wrapper (Array)
    #   expand_detail   — collapsible detail lines (Array); when non-empty, renders expand wrapper
    #   expand_more_count — count passed to i18n hint (Integer)
    #   expand_label    — translated string for the expand hint text
    #   collapse_label  — translated string for the collapse hint text
    class ExpandableBodyComponent < ViewComponent::Base
      def initialize(body: nil, expand_lines: [], expand_detail: [],
                     expand_more_count: 0, expand_label: "", collapse_label: "",
                     html: false)
        @body              = body
        @html              = html == true || html == "true"
        @expand_lines      = expand_lines
        @expand_detail     = expand_detail
        @expand_more_count = expand_more_count
        @expand_label      = expand_label
        @collapse_label    = collapse_label
      end

      def expandable? = @expand_detail.any?
      def html?         = @html
    end
  end
end
