require "rails_helper"

# Phase 13.3 — Smuggle / flaw defense for the analytics dashboard.
# Defense-in-depth: even though tenants are gone (ADR 0003) and the
# routes are nested under the channel/video parent, hand-typed URLs
# or tampered POSTs must not be honored if they target the wrong
# resource.
RSpec.describe "Analytics smuggle defense", type: :request do
  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video)   { create(:video, channel: channel) }

  it "ignores a smuggled connection_id parameter on /analytics" do
    other_connection = create(:youtube_connection)
    create(:channel, youtube_connection: other_connection)
    create(:channel, youtube_connection: connection)

    get "/analytics", params: { connection_id: other_connection.id }
    expect(response).to have_http_status(:ok)
    expect(response.body.scan(/class="analytics-channel-card"/).size).to eq(2)
  end

  it "ignores a smuggled tenant_id parameter on /analytics" do
    create(:channel, youtube_connection: connection)
    get "/analytics", params: { tenant_id: 9999 }
    expect(response).to have_http_status(:ok)
  end

  it "rejects a smuggled video_id that does not match the route's video" do
    other_video = create(:video, channel: channel)
    expect {
      post video_analytics_refresh_path(video), params: { video_id: other_video.id }
    }.to change(VideoAnalyticsSync.jobs, :size).by(1)
    enqueued_ids = VideoAnalyticsSync.jobs.map { |j| j["args"].first }
    expect(enqueued_ids).to eq([ video.id ])
    expect(enqueued_ids).not_to include(other_video.id)
  end

  it "rejects a smuggled channel_id that targets a different channel" do
    other_channel = create(:channel, youtube_connection: connection)
    expect {
      post channel_analytics_refresh_path(channel),
           params: { channel_id: other_channel.id }
    }.to change(ChannelAnalyticsSync.jobs, :size).by(1)
    enqueued_ids = ChannelAnalyticsSync.jobs.map { |j| j["args"].first }
    expect(enqueued_ids).to eq([ channel.id ])
  end
end
