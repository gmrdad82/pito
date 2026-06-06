# frozen_string_literal: true

require "rails_helper"

# NOTE: ChannelAnalyticsSync references analytics models (ChannelDaily,
# ChannelWindowSummary, TopVideosWindow) that are not yet in the schema.
# The specs below exercise the job's routing and early-exit logic by
# stubbing the model writes. Full upsert coverage should be added when
# those tables/models are introduced.

RSpec.describe ChannelAnalyticsSync, type: :job do
  let(:connection) { create(:youtube_connection) }
  let(:channel)    { create(:channel, youtube_connection: connection) }

  let(:analytics_client_double) do
    instance_double(Channel::Youtube::AnalyticsClient,
                    today_pt:               Date.current,
                    channel_daily:          { column_headers: [], rows: [] },
                    channel_window_summary: { column_headers: [], rows: [] },
                    top_videos:             { column_headers: [], rows: [] })
  end

  before do
    allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(analytics_client_double)

    # Stub the non-existent AR models so the job can run without raising
    # NameError / uninitialized constant.
    stub_const("ChannelDaily",         double(upsert_all: nil))
    stub_const("ChannelWindowSummary", double(upsert_all: nil))
    stub_const("TopVideosWindow", Class.new do
      def self.where(...) = where_double
      def self.where_double = double(delete_all: nil)
      def self.upsert_all(...) = nil
      def self.transaction(&block) = block.call
    end)
    allow(TopVideosWindow).to receive(:where).and_return(double(delete_all: nil))
    allow(TopVideosWindow).to receive(:transaction).and_yield
    allow(TopVideosWindow).to receive(:upsert_all)
  end

  describe "#perform" do
    it "exits early when the channel does not exist" do
      expect(Channel::Youtube::AnalyticsClient).not_to receive(:new)
      described_class.new.perform(0)
    end

    it "exits early when the connection is nil" do
      channel.update_column(:youtube_connection_id, nil)
      expect(Channel::Youtube::AnalyticsClient).not_to receive(:new)
      described_class.new.perform(channel.id)
    end

    it "exits early when the connection needs_reauth" do
      connection.update!(needs_reauth: true)
      expect(Channel::Youtube::AnalyticsClient).not_to receive(:new)
      described_class.new.perform(channel.id)
    end

    it "instantiates AnalyticsClient and calls channel_daily" do
      expect(analytics_client_double).to receive(:channel_daily).and_return(
        { column_headers: [], rows: [] }
      )
      described_class.new.perform(channel.id)
    end

    it "calls window summary and top_videos for each WINDOW" do
      expect(analytics_client_double).to receive(:channel_window_summary)
        .exactly(Channel::Youtube::AnalyticsQueryBuilder::WINDOWS.size).times
        .and_return({ column_headers: [], rows: [] })
      expect(analytics_client_double).to receive(:top_videos)
        .exactly(Channel::Youtube::AnalyticsQueryBuilder::WINDOWS.size).times
        .and_return({ column_headers: [], rows: [] })
      described_class.new.perform(channel.id)
    end

    context "when AuthError is raised" do
      before do
        allow(analytics_client_double).to receive(:channel_daily).and_raise(
          Channel::Youtube::AnalyticsClient::AuthError, "auth failed"
        )
      end

      it "does not propagate the error" do
        expect { described_class.new.perform(channel.id) }.not_to raise_error
      end
    end
  end
end
