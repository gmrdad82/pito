# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Warmup do
  let(:channel) { create(:channel, :on_connection) }

  # Derived from the real ontology, not hardcoded — the spec tracks whatever
  # GLANCE_METRICS / MetricOrder define, rather than drifting from them.
  let(:glance_keys)      { Pito::Analytics::ScalarsTableComponent::GLANCE_METRICS.map { |m| m[:key].to_s } }
  let(:system_metrics)   { Pito::Analytics::MetricOrder.for(role: :system,   level: :channel) }
  let(:enhanced_metrics) { Pito::Analytics::MetricOrder.for(role: :enhanced, level: :channel) }

  before do
    allow(Pito::Analytics::MetricFill).to receive(:for).and_return(:warmed)
    allow(Pito::Analytics::AnalyzeMetricFill).to receive(:for).and_return(:warmed)
  end

  describe "glance fan-out (MetricFill)" do
    it "fills every glance key for both periods (2 periods × 5 keys = 10 calls)" do
      described_class.call(channel:)

      expect(Pito::Analytics::MetricFill).to have_received(:for)
        .exactly(Pito::Analytics::Warmup::PERIODS.size * glance_keys.size).times

      Pito::Analytics::Warmup::PERIODS.each do |period|
        glance_keys.each do |key|
          expect(Pito::Analytics::MetricFill).to have_received(:for).with(scope: channel, period:, key:)
        end
      end
    end
  end

  describe "analyze fan-out (AnalyzeMetricFill)" do
    it "fills every :system metric per period, plus every :enhanced metric once at lifetime (2×6 + 8 = 20 calls)" do
      described_class.call(channel:)

      expected_count = (Pito::Analytics::Warmup::PERIODS.size * system_metrics.size) + enhanced_metrics.size
      expect(Pito::Analytics::AnalyzeMetricFill).to have_received(:for).exactly(expected_count).times

      Pito::Analytics::Warmup::PERIODS.each do |period|
        system_metrics.each do |metric|
          expect(Pito::Analytics::AnalyzeMetricFill).to have_received(:for)
            .with(metric:, level: :channel, entity_ids: [ channel.id ], period:)
        end
      end
    end

    it "fills every :enhanced metric ONCE at the lifetime period, regardless of the 7d/28d loop" do
      described_class.call(channel:)

      enhanced_metrics.each do |metric|
        expect(Pito::Analytics::AnalyzeMetricFill).to have_received(:for)
          .with(metric:, level: :channel, entity_ids: [ channel.id ], period: "lifetime").once
      end
    end

    it "spot-checks retention at lifetime (breakdown/retention warming)" do
      described_class.call(channel:)

      expect(Pito::Analytics::AnalyzeMetricFill).to have_received(:for)
        .with(metric: :retention, level: :channel, entity_ids: [ channel.id ], period: "lifetime")
    end

    it "spot-checks views at each period (system role)" do
      described_class.call(channel:)

      expect(Pito::Analytics::AnalyzeMetricFill).to have_received(:for)
        .with(metric: :views, level: :channel, entity_ids: [ channel.id ], period: "7d")
      expect(Pito::Analytics::AnalyzeMetricFill).to have_received(:for)
        .with(metric: :views, level: :channel, entity_ids: [ channel.id ], period: "28d")
    end
  end
end
