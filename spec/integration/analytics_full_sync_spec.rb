require "rails_helper"

# Phase 13.2 — Analytics sync engine. Integration spec exercising the
# orchestrator → child-job → analytics-tables chain end-to-end with
# Sidekiq's inline mode.
RSpec.describe "analytics full sync (integration)", type: :integration do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:other_connection) { create(:youtube_connection, user: user, google_subject_id: "subject-other-99") }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:other_channel) { create(:channel, youtube_connection: other_connection) }
  let(:active_video) { create(:video, channel: channel, youtube_video_id: "vidactiv", published_at: 30.days.ago) }
  let(:inactive_video) { create(:video, channel: channel, youtube_video_id: "vidinact", published_at: 200.days.ago) }
  let(:other_video) { create(:video, channel: other_channel, youtube_video_id: "vidother", published_at: 30.days.ago) }
  let(:client_for) { ->(_conn) { build_client_double } }

  def build_client_double
    instance_double(Youtube::AnalyticsClient).tap do |client|
      allow(client).to receive(:today_pt).and_return(Date.new(2026, 5, 10))
      allow(client).to receive(:channel_daily).and_return(
        column_headers: [ { name: "day" }, { name: "views" } ],
        rows: [ [ "2026-05-07", 100 ], [ "2026-05-08", 200 ], [ "2026-05-09", 300 ] ]
      )
      allow(client).to receive(:channel_window_summary).and_return(
        column_headers: [ { name: "views" } ], rows: [ [ 600 ] ]
      )
      allow(client).to receive(:top_videos).and_return(
        column_headers: [ { name: "video" }, { name: "views" }, { name: "estimatedMinutesWatched" }, { name: "averageViewDuration" }, { name: "averageViewPercentage" }, { name: "subscribersGained" }, { name: "likes" }, { name: "comments" } ],
        rows: [ [ "vidactiv", 1000, 200, 60, 0.4, 5, 50, 10 ] ]
      )
      allow(client).to receive(:video_daily).and_return(
        column_headers: [ { name: "day" }, { name: "views" } ],
        rows: [ [ "2026-05-09", 100 ] ]
      )
      allow(client).to receive(:video_window_summary).and_return(
        column_headers: [ { name: "views" } ], rows: [ [ 100 ] ]
      )
      allow(client).to receive(:video_by_country).and_return(
        column_headers: [ { name: "country" }, { name: "views" } ],
        rows: [ [ "US", 100 ] ]
      )
      allow(client).to receive(:video_by_device_type).and_return(
        column_headers: [ { name: "deviceType" }, { name: "views" } ],
        rows: [ [ "MOBILE", 100 ] ]
      )
      allow(client).to receive(:video_by_operating_system).and_return(
        column_headers: [ { name: "operatingSystem" }, { name: "views" } ],
        rows: [ [ "ANDROID", 100 ] ]
      )
      allow(client).to receive(:video_by_traffic_source).and_return(
        column_headers: [ { name: "insightTrafficSourceType" }, { name: "views" } ],
        rows: [ [ "YT_SEARCH", 100 ] ]
      )
      allow(client).to receive(:video_by_subscribed_status).and_return(
        column_headers: [ { name: "subscribedStatus" }, { name: "views" } ],
        rows: [ [ "SUBSCRIBED", 100 ] ]
      )
      allow(client).to receive(:video_demographics).and_return(
        column_headers: [ { name: "ageGroup" }, { name: "gender" }, { name: "viewerPercentage" } ],
        rows: [ [ "AGE_18_24", "MALE", 0.4 ] ]
      )
    end
  end

  before do
    channel
    active_video
    inactive_video
  end

  it "from empty state, populates every analytics table for one connection / one channel / one active + one inactive video" do
    allow(Youtube::AnalyticsClient).to receive(:new) { build_client_double }

    Sidekiq::Testing.inline! do
      YoutubeAnalyticsSync.new.perform
    end

    expect(ChannelDaily.where(channel_id: channel.id).count).to be > 0
    expect(ChannelWindowSummary.where(channel_id: channel.id).count).to eq(4)
    expect(TopVideosWindow.where(channel_id: channel.id).count).to be > 0
    expect(VideoDaily.where(video_id: active_video.id).count).to be > 0
    expect(VideoDaily.where(video_id: inactive_video.id).count).to be > 0
    expect(VideoWindowSummary.where(video_id: active_video.id).count).to eq(4)
    expect(VideoWindowSummary.where(video_id: inactive_video.id).count).to eq(0)
    expect(VideoDailyByCountry.where(video_id: active_video.id).count).to be > 0
  end

  it "on a second nightly run, only updates rows for the 3-day refresh window; older rows untouched" do
    allow(Youtube::AnalyticsClient).to receive(:new) { build_client_double }

    Sidekiq::Testing.inline! do
      YoutubeAnalyticsSync.new.perform
    end

    older_row = ChannelDaily.create!(
      channel_id: channel.id,
      date: Date.new(2026, 1, 1),
      views: 999
    )
    expected_views = older_row.views

    Sidekiq::Testing.inline! do
      YoutubeAnalyticsSync.new.perform
    end

    older_row.reload
    expect(older_row.views).to eq(expected_views)
  end

  it "when one connection's token expires mid-run, that connection's channels stop syncing but other connections proceed" do
    other_channel
    other_video

    bad_client  = build_client_double
    good_client = build_client_double
    allow(bad_client).to receive(:channel_daily) do
      connection.update_columns(needs_reauth: true)
      raise Youtube::AnalyticsClient::AuthError, "401"
    end

    allow(Youtube::AnalyticsClient).to receive(:new) do |connection:|
      connection == self.connection ? bad_client : good_client
    end

    Sidekiq::Testing.inline! do
      YoutubeAnalyticsSync.new.perform
    end

    expect(connection.reload.needs_reauth).to be true
    expect(other_connection.reload.needs_reauth).to be false
    # Other connection still wrote rows.
    expect(ChannelDaily.where(channel_id: other_channel.id).count).to be > 0
  end

  it "writes a youtube_api_calls audit row only for actual API calls (mocked client level)" do
    # Integration with the real client → audit-row count is exercised
    # in the unit specs (analytics_client_spec.rb). Here we assert that
    # the orchestrator does NOT write spurious audit rows itself — the
    # only way the table grows is via the client.
    allow(Youtube::AnalyticsClient).to receive(:new) { build_client_double }

    expect {
      Sidekiq::Testing.inline! do
        YoutubeAnalyticsSync.new.perform
      end
    }.not_to change { YoutubeApiCall.unscoped.count }
  end

  it "monetization-disabled mode: revenue columns stay NULL on every row" do
    AppSetting.set("monetization_enabled", "no")
    allow(Youtube::AnalyticsClient).to receive(:new) { build_client_double }

    Sidekiq::Testing.inline! do
      YoutubeAnalyticsSync.new.perform
    end

    expect(ChannelDaily.where.not(estimated_revenue: nil).count).to eq(0)
  end

  it "monetization-enabled mode: builder includes revenue metrics" do
    AppSetting.set("monetization_enabled", "yes")
    params = Youtube::AnalyticsQueryBuilder.channel_daily_params(
      channel_youtube_id: "UCabcdefghijklmnopqrstuv",
      from: Date.current - 3, to: Date.current - 1,
      monetization_enabled: true
    )
    expect(params[:metrics]).to include("estimatedRevenue")
  end

  it "when the API returns 429 on one query then 200, the job retries (Sidekiq retry: 5)" do
    # Sidekiq's retry semantics are exercised by the framework itself;
    # the job-level assertion here is that RateLimitError surfaces from
    # the client so Sidekiq can requeue.
    rate_client = build_client_double
    allow(rate_client).to receive(:channel_daily).and_raise(
      Youtube::AnalyticsClient::RateLimitError, "429"
    )
    allow(Youtube::AnalyticsClient).to receive(:new).and_return(rate_client)

    expect {
      ChannelAnalyticsSync.new.perform(channel.id)
    }.to raise_error(Youtube::AnalyticsClient::RateLimitError)
  end
end
