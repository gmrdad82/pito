# frozen_string_literal: true

module Pito
  module Analytics
    # Single-source renderer for ONE analyze metric cell, wrapped in Slots::Regular
    # (the `<token>__metric_<key>` swap target). Picks the visualizer from the cell
    # shape (heart / chart→area / bars / scalar / no_data) and supplies the caption
    # as the wrapper's caption block. Used by BOTH the progressive scaffold (loading
    # skeleton + the persisted/ready render) AND AnalyzeMetricJob (the per-metric
    # live swap), so a cell renders identically in every path.
    #
    # The cell hash comes either fresh from Pito::Analytics::AnalyzeMetricFill
    # (symbol-keyed) or re-read from the jsonb marker (string-keyed); we
    # deep-symbolize so the visualizers always see the symbol-keyed shape they
    # expect.
    class AnalyzeCellComponent < ViewComponent::Base
      # @param key     [Symbol, String] metric key → dom-id `<token>__metric_<key>`
      # @param token   [String, nil]
      # @param cell    [Hash, nil]      AnalyzeMetricFill cell hash; nil when loading
      # @param loading [Boolean]        true → loading skeleton (NoData + dot-comet)
      def initialize(key:, token: nil, cell: nil, loading: false)
        @key     = key.to_s
        @token   = token
        @cell    = cell&.deep_symbolize_keys
        @loading = loading
      end

      attr_reader :key, :token, :cell

      def loading? = @loading
      def no_data? = !@loading && @cell.present? && @cell[:no_data]
      def heart?   = @cell.present? && @cell[:heart].present?
      def chart?   = @cell.present? && @cell[:chart].present?
      def bars?    = @cell.present? && @cell[:bars].present?
      def heatmap? = @cell.present? && @cell[:heatmap].present?

      def caption = @cell && @cell[:caption]

      # The metric caption, in the same chrome the visualizers used to render it
      # (now owned by the wrapper). Blank → nothing (Slots::Regular renders no <p>).
      def caption_p(text)
        return "" if text.blank?

        tag.p(text.to_s.html_safe, class: "pito-metric__caption text-fg-dim") # rubocop:disable Rails/OutputSafety
      end
    end
  end
end
