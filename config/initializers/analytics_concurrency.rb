# frozen_string_literal: true

# Environment-differentiated analytics fetch fan-out.
#
# Pito::Analytics::Primitives::MAX_FETCH_CONCURRENCY (8) is the PRODUCTION
# ceiling, sized for the Hetzner CX23 (2 vCPU / 4GB) together with the
# database.yml pool arithmetic. The 64GB dev laptop can fan wider for
# snappier manual testing — its pool is sized to match (database.yml
# development block). Test forces 1 (spec/support/analytics_primitives.rb):
# threaded writes would escape the per-example transaction.
#
# to_prepare: Primitives is app code, so dev code-reloads rebuild the class
# and would drop a one-shot assignment — re-apply on every prepare.
Rails.application.config.to_prepare do
  Pito::Analytics::Primitives.max_concurrency = 12 if Rails.env.development?
end
