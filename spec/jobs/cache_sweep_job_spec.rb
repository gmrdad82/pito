# frozen_string_literal: true

require "rails_helper"

RSpec.describe CacheSweepJob do
  it "sweeps expired analytics_cache rows and keeps live ones" do
    expired = create(:analytics_cache, :ready, expires_at: 1.hour.ago)
    live    = create(:analytics_cache, :ready, expires_at: 1.hour.from_now)

    described_class.perform_now

    expect(AnalyticsCache.exists?(expired.id)).to be(false)
    expect(AnalyticsCache.exists?(live.id)).to be(true)
  end

  it "sweeps expired primitives but never frozen (expires_at NULL) or warm rows" do
    expired = create(:analytics_primitive, :expired)
    frozen  = create(:analytics_primitive, :frozen)
    warm    = create(:analytics_primitive, :live)

    described_class.perform_now

    expect(AnalyticsPrimitive.exists?(expired.id)).to be(false)
    expect(AnalyticsPrimitive.exists?(frozen.id)).to be(true)
    expect(AnalyticsPrimitive.exists?(warm.id)).to be(true)
  end

  it "deletes api_requests older than the 90-day retention and keeps newer ones" do
    old    = ApiRequest.create!(provider: "youtube", created_at: 91.days.ago)
    recent = ApiRequest.create!(provider: "youtube", created_at: 89.days.ago)

    described_class.perform_now

    expect(ApiRequest.exists?(old.id)).to be(false)
    expect(ApiRequest.exists?(recent.id)).to be(true)
  end

  it "returns the per-table sweep counts" do
    create(:analytics_primitive, :expired)

    expect(described_class.perform_now)
      .to eq(analytics_cache: 0, primitives: 1, api_requests: 0)
  end
end
