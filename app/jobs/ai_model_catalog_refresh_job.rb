# frozen_string_literal: true

# Nightly AI model-catalog refresh (owner call: once nightly — the lazy TTL
# re-fetches during use aren't wanted).
#
# For every provider whose catalog fetch can actually succeed — a key on
# file, or OpenCode Zen (lists models unauthenticated) — bust the cache and
# re-fetch, so picker lists renew once a night instead of on demand. (Costs
# are provider-REPORTED per answer, T16.22 — nothing here prices anything.)
# A provider that fails mid-run just keeps its stale-or-pinned fallback
# (ModelCatalog#fetch_live never raises past its own logging) and the rest
# of the loop continues.
class AiModelCatalogRefreshJob < ApplicationJob
  queue_as :default

  # Providers refreshed even without a stored key (see class doc).
  KEYLESS_PROVIDERS = %i[opencode].freeze

  def perform
    Ai::ProviderRegistry.provider_names.each do |name|
      next unless refreshable?(name)

      Ai::ModelCatalog.bust!(provider: name)
      Ai::ModelCatalog.models(provider: name)
    end
  end

  private

  def refreshable?(name)
    KEYLESS_PROVIDERS.include?(name.to_sym) ||
      AppSetting.get("#{name}_api_key").present?
  end
end
