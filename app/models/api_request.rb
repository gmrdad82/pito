# frozen_string_literal: true

# A single outbound external-API request, logged by the instrumentation shims
# at each provider chokepoint: IGDB (Game::Igdb::Client), YouTube
# (Channel::Youtube::Auditor), the local embedder (Pito::Embedding::Client),
# the NL mapper (Pito::Nl::CompletionClient), and the AI wire
# (Ai::Wire::AnthropicMessages / Ai::Wire::OpenAiChat). Pito::Stack counts
# these over rolling 24h and current-month windows.
#
#   ApiRequest.record!(provider: "igdb", endpoint: "/games")
#   ApiRequest.igdb.last_24h.count
#
# `units` is optional (YouTube quota units, embed/completion/token counts for
# the other providers); request COUNT is what Pito::Stack reports. Rows are
# pruned to ~2 months by Pito::Stack housekeeping.
#
# PROVIDERS must mirror every literal string passed as `Pito::Stack.track`'s
# first arg — `Stack.track` rescues StandardError, so a provider missing here
# makes `ApiRequest.create!`'s RecordInvalid raise and get silently swallowed
# (no row, no error surfaced). grep `Pito::Stack.track(` across app/ lib/ to
# re-verify this list after adding a new instrumented client.
class ApiRequest < ApplicationRecord
  PROVIDERS = %w[igdb youtube embedding nlmapper ai].freeze

  validates :provider, presence: true, inclusion: { in: PROVIDERS }

  scope :for_provider, ->(provider) { where(provider: provider.to_s) }
  scope :last_24h,   -> { where(created_at: 24.hours.ago..) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..) }

  PROVIDERS.each do |p|
    scope p, -> { for_provider(p) }
  end

  # Logs one request. created_at is set automatically by Rails.
  def self.record!(provider:, endpoint: nil, units: nil)
    create!(provider: provider.to_s, endpoint: endpoint, units: units)
  end

  # Housekeeping: drop rows older than the retention window (default 2 months).
  def self.prune!(older_than: 2.months.ago)
    where(created_at: ...older_than).delete_all
  end
end
