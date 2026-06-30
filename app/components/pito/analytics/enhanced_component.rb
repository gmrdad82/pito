# frozen_string_literal: true

module Pito
  module Analytics
    # The filled analytics :enhanced body: the (stable) intro line followed by a
    # flex panel holding the scalar kv-table — room on the right for future
    # widgets. When analytics couldn't be fetched (reauth / API error) it shows a
    # brief note instead of the table. Rendered by Pito::MessageBuilder::Analytics
    # once AnalyticsFillJob has the data.
    class EnhancedComponent < ViewComponent::Base
      # @param token [String, nil] per-message hex token threaded from the pending
      #   marker — used to build stable dom-ids on the ScalarsTableComponent cells
      #   so Turbo Stream per-metric fills can target them by id.
      def initialize(intro:, result: nil, pending: false, nudge: nil, series: {}, token: nil)
        @intro   = intro
        @result  = result
        @pending = pending
        @nudge   = nudge
        @series  = series || {}
        @token   = token
      end

      def pending?
        @pending
      end

      def unavailable?
        return false if pending?

        @result.nil? || @result == Pito::Analytics::Scalars::UNAVAILABLE
      end
    end
  end
end
