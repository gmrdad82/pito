# frozen_string_literal: true

module Pito
  module Analytics
    # The `analyze` `:system`/`:enhanced` message body: the (stable) intro line + a
    # grid of generic `Slots::Compact` cells. For now every cell shows a
    # `0`/`1` data-pulled scaffold value (real per-metric components come on the
    # owner's "revisit"). Mirrors `EnhancedComponent`'s intro/pending shape (inline
    # `data-pito-ts-slot`, spinner while the fan-out runs) but renders the analyze
    # cells instead of the scalars table — keeping the analyze + show stacks isolated.
    class ScaffoldComponent < ViewComponent::Base
      # @param intro   [String] pre-rendered html-safe intro
      # @param cells   [Array<Hash>] { label:, value: } per metric (value e.g. "1"/"0")
      # @param pending [Boolean] true while the fan-out is still running
      def initialize(intro:, cells: nil, pending: false)
        @intro   = intro
        @cells   = cells || []
        @pending = pending
      end

      def pending? = @pending
    end
  end
end
