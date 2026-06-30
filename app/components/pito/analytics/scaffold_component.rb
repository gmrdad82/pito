# frozen_string_literal: true

module Pito
  module Analytics
    # The `analyze` `:system`/`:enhanced` message body: the (stable) intro line + a
    # grid of metric cells.
    #
    # Two render modes:
    #   PENDING (progressive) — the fan-out hasn't filled the data yet. Renders one
    #     LOADING cell per `metric_keys` entry (NoData canvas + dot-comet caption),
    #     each an AnalyzeCellComponent with a `<token>__metric_<key>` dom-id so the
    #     per-metric AnalyzeMetricJob can swap it in independently as it lands.
    #   READY — the (re-fetched) aggregate is in; renders the filled `cells`
    #     (heart / area / bar / no-data / scalar) via the visualizers. (Built by
    #     Message#ready_payload, unchanged.)
    class ScaffoldComponent < ViewComponent::Base
      # @param intro       [String] pre-rendered html-safe intro
      # @param cells       [Array<Hash>] filled cells (ready render)
      # @param pending     [Boolean] true → progressive loading cells
      # @param token       [String, nil] per-message token for the cell dom-ids
      # @param metric_keys [Array<String>] ordered metric keys (pending render)
      def initialize(intro:, cells: nil, pending: false, token: nil, metric_keys: nil)
        @intro       = intro
        @cells       = cells || []
        @pending     = pending
        @token       = token
        @metric_keys = Array(metric_keys).map(&:to_s)
      end

      def pending? = @pending

      attr_reader :token, :metric_keys
    end
  end
end
