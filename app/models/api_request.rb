# frozen_string_literal: true

# A single outbound external-API request, logged by the instrumentation shims
# at each provider chokepoint (Voyage / IGDB / YouTube). Pito::Stack counts
# these over rolling 24h and current-month windows.
#
#   ApiRequest.record!(provider: "igdb", endpoint: "/games")
#   ApiRequest.voyage.last_24h.count
#
# `units` is optional (YouTube quota units); request COUNT is what Pito::Stack
# reports. Rows are pruned to ~2 months by Pito::Stack housekeeping.
class ApiRequest < ApplicationRecord
  PROVIDERS = %w[voyage igdb youtube].freeze

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
