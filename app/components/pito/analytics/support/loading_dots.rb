# frozen_string_literal: true

module Pito
  module Analytics
    module Support
      # A small (~50% of the chatbar comet) activity indicator shown in a metric's
      # SCALAR slot while its value is still loading (item 5 progressive glance).
      # Same dots/comet animation as `Pito::Shell::PostCommandDotsComponent`, half
      # the size, with a per-instance start-stagger (seeded) so several loaders on
      # screen never pulse in sync.
      class LoadingDots < ViewComponent::Base
        DOTS    = 8
        BUCKETS = 5

        # @param seed [Object] anything stable per slot (e.g. the metric key) — picks
        #   one of BUCKETS animation-delay buckets so adjacent loaders are out of phase.
        def initialize(seed: nil)
          @seed = seed
        end

        def delay_class
          bucket = @seed.to_s.each_byte.sum % BUCKETS
          "pito-loading-dots--d#{bucket}"
        end
      end
    end
  end
end
