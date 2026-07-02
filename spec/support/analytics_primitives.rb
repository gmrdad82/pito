# frozen_string_literal: true

# Cold primitive fetches fan out over a bounded thread pool (0.9.0 Phase 3).
# Under transactional examples a thread's writes would use a DIFFERENT pooled
# connection — outside the example's transaction — and leak rows across
# examples. Force the sequential path suite-wide; the dedicated parallel spec
# (spec/services/pito/analytics/primitives_parallel_spec.rb) opts back in
# inside a non-transactional group.
RSpec.configure do |config|
  config.before do
    Pito::Analytics::Primitives.max_concurrency = 1
  end
end
