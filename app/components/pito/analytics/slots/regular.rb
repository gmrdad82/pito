# frozen_string_literal: true

module Pito
  module Analytics
    module Slots
      # REGULAR-size metric cell wrapper — the `<token>__metric_<key>` swap target
      # for large visualizers (area chart, heart, bar). Analog of Slots::Compact for
      # the regular (full-canvas) visualizer stack.
      #
      # Three render branches:
      #   loading:  NoData(:regular) canvas + LoadingDots where the caption goes
      #             (NOT the visualizer/caption slots).
      #   no_data:  NoData(:regular) canvas + caption slot (terminal state).
      #   filled:   visualizer slot + caption slot beneath it.
      #
      # Callers provide the visualizer + caption as content slots; this wrapper
      # owns the stable dom-id so the broadcaster fragment swap always lands.
      class Regular < ViewComponent::Base
        renders_one :visualizer
        renders_one :caption

        # @param key     [Symbol, String] metric key → dom-id `<token>__metric_<key>`
        # @param token   [String, nil]    per-message token for the stable dom-id
        # @param loading [Boolean]        true → NoData(:regular) + LoadingDots skeleton
        # @param no_data [Boolean]        true → NoData(:regular) + caption slot (terminal)
        def initialize(key:, token: nil, loading: false, no_data: false)
          @key     = key
          @token   = token
          @loading = loading
          @no_data = no_data
        end

        attr_reader :key

        def loading? = @loading
        def no_data? = @no_data
        def dom_id   = @token ? "#{@token}__metric_#{@key}" : nil
      end
    end
  end
end
