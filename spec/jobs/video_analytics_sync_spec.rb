# frozen_string_literal: true

require "rails_helper"

# NOTE: VideoAnalyticsSync references analytics models (VideoDaily,
# VideoWindowSummary, VideoDailyByCountry, etc.) that are not yet in the
# schema. The specs below exercise routing and early-exit logic by stubbing
# those model writes. Full upsert coverage should be added once those
# tables/models are introduced.

RSpec.describe VideoAnalyticsSync, type: :job do
  let(:connection) { create(:youtube_connection) }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:video)      { create(:video, channel: channel) }

  let(:empty_response) { { column_headers: [], rows: [] } }

  let(:analytics_client_double) do
    instance_double(Channel::Youtube::AnalyticsClient,
                    today_pt:                    Date.current,
                    video_daily:                 empty_response,
                    video_window_summary:        empty_response,
                    video_by_country:            empty_response,
                    video_by_device_type:        empty_response,
                    video_by_operating_system:   empty_response,
                    video_by_traffic_source:     empty_response,
                    video_by_subscribed_status:  empty_response,
                    video_demographics:          empty_response)
  end

  before do
    allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(analytics_client_double)

    # Stub the non-existent AR models so the job can run without NameError.
    %w[
      VideoDaily VideoWindowSummary VideoDailyByCountry VideoDailyByDeviceType
      VideoDailyByOperatingSystem VideoDailyByTrafficSource
      VideoDailyBySubscribedStatus VideoDailyByAgeGroupGender
    ].each do |klass|
      stub_const(klass, double(upsert_all: nil))
    end

    # ActiveVideoClassifier — stub active? so we exercise the active path.
    allow(Channel::Youtube::ActiveVideoClassifier).to receive(:active?).and_return(true)
  end

  describe "#perform" do
    it "exits early when the video does not exist" do
      expect(Channel::Youtube::AnalyticsClient).not_to receive(:new)
      described_class.new.perform(0)
    end

    it "exits early when the channel's connection needs_reauth" do
      connection.update!(needs_reauth: true)
      expect(Channel::Youtube::AnalyticsClient).not_to receive(:new)
      described_class.new.perform(video.id)
    end

    it "calls video_daily for any video" do
      expect(analytics_client_double).to receive(:video_daily).and_return(empty_response)
      described_class.new.perform(video.id)
    end

    it "calls window summary and geo/device calls for active videos" do
      expect(analytics_client_double).to receive(:video_window_summary)
        .exactly(Channel::Youtube::AnalyticsQueryBuilder::WINDOWS.size).times
        .and_return(empty_response)
      expect(analytics_client_double).to receive(:video_by_country).and_return(empty_response)
      expect(analytics_client_double).to receive(:video_by_device_type).and_return(empty_response)
      expect(analytics_client_double).to receive(:video_by_operating_system).and_return(empty_response)
      expect(analytics_client_double).to receive(:video_by_traffic_source).and_return(empty_response)
      expect(analytics_client_double).to receive(:video_by_subscribed_status).and_return(empty_response)
      expect(analytics_client_double).to receive(:video_demographics).and_return(empty_response)
      described_class.new.perform(video.id)
    end

    context "for an inactive video" do
      before { allow(Channel::Youtube::ActiveVideoClassifier).to receive(:active?).and_return(false) }

      it "calls only video_daily (no window/geo calls)" do
        expect(analytics_client_double).to receive(:video_daily).and_return(empty_response)
        expect(analytics_client_double).not_to receive(:video_window_summary)
        expect(analytics_client_double).not_to receive(:video_by_country)
        described_class.new.perform(video.id)
      end
    end

    context "when AuthError is raised" do
      before do
        allow(analytics_client_double).to receive(:video_daily).and_raise(
          Channel::Youtube::AnalyticsClient::AuthError, "auth failed"
        )
      end

      it "does not propagate the error" do
        expect { described_class.new.perform(video.id) }.not_to raise_error
      end
    end
  end
end
