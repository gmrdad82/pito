# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Scaffold do
  let(:channel) { create(:channel, :on_connection, youtube_channel_id: "yt_ch") }
  let(:window)  { Pito::Analytics::Window.for("7d", reference_date: Date.new(2026, 6, 25)) }
  let(:groups)  { [ [ channel, %w[v1] ] ] }

  describe ".for" do
    it "is true for metrics whose report returned data, false otherwise" do
      # subscribed_status moved to :enhanced; check its own (empty) report there
      # alongside devices (own report, has data). Retention is now available at
      # channel level too, so stub its single-video probe to return no rows.
      allow(Pito::Analytics::Primitives).to receive(:fetch) do |report:, **|
        report == "device" ? { "v1" => [ { "device_type" => "MOBILE", "views" => 10 } ] } : {}
      end
      allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(
        instance_double(Channel::Youtube::AnalyticsClient, retention: [])
      )

      result = described_class.for(groups:, window:, role: :enhanced, level: :channel)

      expect(result[:devices]).to be(true)            # device report → data
      expect(result[:subscribed_status]).to be(false) # own report, empty
    end

    it "gives metrics sharing one report the same flag" do
      allow(Pito::Analytics::Primitives).to receive(:fetch).and_return({})

      # views/subs/likes all share the scalars report in :system (comments moved to
      # :enhanced as an area chart).
      result = described_class.for(groups:, window:, role: :system, level: :vid)
      expect(result.values_at(:views, :subs, :likes)).to all(be(false))
    end

    it "treats a report that errors as not-pulled (rescued)" do
      allow(Pito::Analytics::Primitives).to receive(:fetch).and_raise(StandardError, "boom")

      expect(described_class.for(groups:, window:, role: :system, level: :vid)[:views]).to be(false)
    end

    it "fetches one report per group even when many metrics share it (memoised)" do
      allow(Pito::Analytics::Primitives).to receive(:fetch).and_return({ "v1" => { "views" => 1 } })
      described_class.for(groups:, window:, role: :system, level: :vid)
      # :system now needs only the scalars report (subscribed_status moved to :enhanced)
      expect(Pito::Analytics::Primitives).to have_received(:fetch).once
    end
  end

  describe "retention (special single-video probe path)" do
    it "probes the first video and is true when retention rows return" do
      allow(Pito::Analytics::Primitives).to receive(:fetch).and_return({})
      client = instance_double(Channel::Youtube::AnalyticsClient, retention: [ { elapsed_video_time_ratio: 0.0 } ])
      allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(client)

      result = described_class.for(groups:, window:, role: :enhanced, level: :vid)
      expect(result[:retention]).to be(true)
    end

    it "is false when retention returns no rows" do
      allow(Pito::Analytics::Primitives).to receive(:fetch).and_return({})
      client = instance_double(Channel::Youtube::AnalyticsClient, retention: [])
      allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(client)

      expect(described_class.for(groups:, window:, role: :enhanced, level: :vid)[:retention]).to be(false)
    end
  end
end
