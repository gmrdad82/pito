# frozen_string_literal: true

require "rails_helper"

RSpec.describe AchievementsRefreshJob, type: :job do
  include ActiveJob::TestHelper

  # ─── helpers ────────────────────────────────────────────────────────────────

  # Build a minimal analytics top_videos row.
  def make_analytics_row(video_id, views: 1000, minutes: 6000, subs_gained: 5)
    {
      video_id:                  video_id,
      views:                     views,
      estimated_minutes_watched: minutes,
      subscribers_gained:        subs_gained,
      subscribers_lost:          0
    }
  end

  # Build a minimal videos_list response item (likes + comments from Data API).
  def make_video_item(id, likes: "50", comments: "10")
    {
      id:         id,
      statistics: { like_count: likes, comment_count: comments }
    }
  end

  # Build a minimal channels_list response item.
  def make_channel_item(channel_id, subscriber_count: "2000")
    {
      id:         channel_id,
      statistics: { subscriber_count: subscriber_count }
    }
  end

  # ─── shared setup ───────────────────────────────────────────────────────────

  let(:connection)  { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCprimary",
           title: "Primary Channel")
  end
  let!(:video) { create(:video, channel: channel, youtube_video_id: "vid_aaa") }
  let!(:game)  { create(:game) }
  let!(:link)  { create(:video_game_link, video: video, game: game) }

  let(:analytics_client) { instance_double(Channel::Youtube::AnalyticsClient) }
  let(:data_client)      { instance_double(Channel::Youtube::Client) }

  before do
    allow(Channel::Youtube::AnalyticsClient).to receive(:new).with(connection).and_return(analytics_client)
    allow(Channel::Youtube::Client).to receive(:new).with(connection).and_return(data_client)

    allow(analytics_client).to receive(:top_videos).and_return([
      make_analytics_row("vid_aaa", views: 1200, minutes: 3600, subs_gained: 8)
    ])
    allow(data_client).to receive(:videos_list).and_return(
      { items: [ make_video_item("vid_aaa", likes: "40", comments: "12") ] }
    )
    allow(data_client).to receive(:channels_list).and_return(
      { items: [ make_channel_item("UCprimary", subscriber_count: "5000") ] }
    )
  end

  subject(:job) { described_class.new }

  # ─── analytics client call ──────────────────────────────────────────────────

  describe "Analytics API call" do
    it "calls top_videos with the explicit channel_id, lifetime start, and today" do
      expect(analytics_client).to receive(:top_videos).with(
        channel_id: "UCprimary",
        start_date: described_class::LIFETIME_START,
        end_date:   Date.current
      ).and_return([])

      job.perform
    end
  end

  # ─── AchievementMetric rows — video ─────────────────────────────────────────

  describe "video AchievementMetric rows" do
    before { job.perform }

    it "writes the views metric for the video" do
      row = AchievementMetric.find_by(achievable: video, metric: "views")
      expect(row&.value).to eq(1200)
    end

    it "converts estimated_minutes_watched to watched_hours (integer division)" do
      # 3600 minutes / 60 = 60 hours
      row = AchievementMetric.find_by(achievable: video, metric: "watched_hours")
      expect(row&.value).to eq(60)
    end

    it "writes the subs_gained metric for the video" do
      row = AchievementMetric.find_by(achievable: video, metric: "subs_gained")
      expect(row&.value).to eq(8)
    end

    it "writes the likes metric for the video" do
      row = AchievementMetric.find_by(achievable: video, metric: "likes")
      expect(row&.value).to eq(40)
    end

    it "writes the comments metric for the video" do
      row = AchievementMetric.find_by(achievable: video, metric: "comments")
      expect(row&.value).to eq(12)
    end
  end

  # ─── AchievementMetric rows — channel ───────────────────────────────────────

  describe "channel AchievementMetric rows" do
    before { job.perform }

    it "writes the subs metric from channels_list for the channel" do
      row = AchievementMetric.find_by(achievable: channel, metric: "subs")
      expect(row&.value).to eq(5000)
    end

    it "writes channel views as the sum of its videos" do
      row = AchievementMetric.find_by(achievable: channel, metric: "views")
      expect(row&.value).to eq(1200)
    end

    it "writes channel watched_hours as the sum of its videos" do
      row = AchievementMetric.find_by(achievable: channel, metric: "watched_hours")
      expect(row&.value).to eq(60)
    end

    it "writes channel likes as the sum of its videos" do
      row = AchievementMetric.find_by(achievable: channel, metric: "likes")
      expect(row&.value).to eq(40)
    end

    it "writes channel comments as the sum of its videos" do
      row = AchievementMetric.find_by(achievable: channel, metric: "comments")
      expect(row&.value).to eq(12)
    end
  end

  # ─── AchievementMetric rows — game ──────────────────────────────────────────

  describe "game AchievementMetric rows" do
    before { job.perform }

    it "writes game views as the sum of its linked videos" do
      row = AchievementMetric.find_by(achievable: game, metric: "views")
      expect(row&.value).to eq(1200)
    end

    it "writes game watched_hours as the sum of its linked videos" do
      row = AchievementMetric.find_by(achievable: game, metric: "watched_hours")
      expect(row&.value).to eq(60)
    end

    it "writes game subs_gained as the sum of its linked videos" do
      row = AchievementMetric.find_by(achievable: game, metric: "subs_gained")
      expect(row&.value).to eq(8)
    end

    it "writes game likes as the sum of its linked videos" do
      row = AchievementMetric.find_by(achievable: game, metric: "likes")
      expect(row&.value).to eq(40)
    end

    it "writes game comments as the sum of its linked videos" do
      row = AchievementMetric.find_by(achievable: game, metric: "comments")
      expect(row&.value).to eq(12)
    end
  end

  # ─── game aggregates across multiple channels ────────────────────────────────

  describe "cross-channel game aggregation" do
    let(:connection2) { create(:youtube_connection) }
    let!(:channel2) do
      create(:channel,
             youtube_connection: connection2,
             youtube_channel_id: "UCsecond",
             title: "Second Channel")
    end
    let!(:video2) { create(:video, channel: channel2, youtube_video_id: "vid_bbb") }
    let!(:link2)  { create(:video_game_link, video: video2, game: game) }

    let(:analytics_client2) { instance_double(Channel::Youtube::AnalyticsClient) }
    let(:data_client2)      { instance_double(Channel::Youtube::Client) }

    before do
      allow(Channel::Youtube::AnalyticsClient).to receive(:new).with(connection2).and_return(analytics_client2)
      allow(Channel::Youtube::Client).to receive(:new).with(connection2).and_return(data_client2)

      allow(analytics_client2).to receive(:top_videos).and_return([
        make_analytics_row("vid_bbb", views: 800, minutes: 1200, subs_gained: 3)
      ])
      allow(data_client2).to receive(:videos_list).and_return(
        { items: [ make_video_item("vid_bbb", likes: "20", comments: "5") ] }
      )
      allow(data_client2).to receive(:channels_list).and_return(
        { items: [ make_channel_item("UCsecond", subscriber_count: "1000") ] }
      )
    end

    it "sums views across both channels' videos for the shared game" do
      job.perform
      row = AchievementMetric.find_by(achievable: game, metric: "views")
      expect(row&.value).to eq(1200 + 800)
    end

    it "sums likes across both channels' videos for the shared game" do
      job.perform
      row = AchievementMetric.find_by(achievable: game, metric: "likes")
      expect(row&.value).to eq(40 + 20)
    end
  end

  # ─── Achievement milestones unlocked ────────────────────────────────────────

  describe "Achievement milestone unlocking" do
    it "unlocks every threshold ≤ value for a video views metric" do
      # 1200 views → thresholds 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000 all ≤ 1200
      job.perform
      unlocked = Achievement.where(achievable: video, metric: "views").pluck(:threshold).sort
      expect(unlocked).to include(1, 2, 5, 10, 100, 1_000)
      expect(unlocked).not_to include(2_000)
    end

    it "unlocks the subs threshold for a channel that has 5000 subscribers" do
      job.perform
      unlocked = Achievement.where(achievable: channel, metric: "subs").pluck(:threshold).sort
      expect(unlocked).to include(1_000, 2_000, 5_000)
      expect(unlocked).not_to include(10_000)
    end

    it "unlocks game thresholds when the video game sum crosses a milestone" do
      job.perform
      unlocked = Achievement.where(achievable: game, metric: "views").pluck(:threshold).sort
      expect(unlocked).to include(1_000)
    end

    it "is idempotent — re-running the job does not duplicate Achievement rows" do
      job.perform
      count_after_first = Achievement.count
      job.perform
      expect(Achievement.count).to eq(count_after_first)
    end
  end

  # ─── error isolation — channel ───────────────────────────────────────────────

  describe "per-channel error isolation" do
    let(:connection2) { create(:youtube_connection) }
    let!(:channel2) do
      create(:channel,
             youtube_connection: connection2,
             youtube_channel_id: "UCsecond",
             title: "Second Channel")
    end
    let!(:video2) { create(:video, channel: channel2, youtube_video_id: "vid_bbb") }

    let(:analytics_client2) { instance_double(Channel::Youtube::AnalyticsClient) }
    let(:data_client2)      { instance_double(Channel::Youtube::Client) }

    before do
      allow(Channel::Youtube::AnalyticsClient).to receive(:new).with(connection2).and_return(analytics_client2)
      allow(Channel::Youtube::Client).to receive(:new).with(connection2).and_return(data_client2)

      # channel's analytics client raises; channel2's succeeds
      allow(analytics_client).to receive(:top_videos).and_raise(StandardError, "analytics boom")

      allow(analytics_client2).to receive(:top_videos).and_return([
        make_analytics_row("vid_bbb", views: 500, minutes: 600, subs_gained: 2)
      ])
      allow(data_client2).to receive(:videos_list).and_return(
        { items: [ make_video_item("vid_bbb", likes: "5", comments: "1") ] }
      )
      allow(data_client2).to receive(:channels_list).and_return(
        { items: [ make_channel_item("UCsecond", subscriber_count: "300") ] }
      )
    end

    it "does not raise even if one channel's client errors" do
      expect { job.perform }.not_to raise_error
    end

    it "logs the error for the failing channel" do
      expect(Rails.logger).to receive(:error)
        .with(/AchievementsRefreshJob.*channel=#{channel.id}.*analytics boom/)
      job.perform
    end

    it "still writes metrics for the channel that succeeded" do
      job.perform
      row = AchievementMetric.find_by(achievable: video2, metric: "views")
      expect(row&.value).to eq(500)
    end
  end

  # ─── shiny-unlock notifications ─────────────────────────────────────────────

  describe "shiny-unlock notifications" do
    it "creates one Notification per newly-unlocked Achievement" do
      job.perform
      # Every newly-created Achievement must have a matching Notification.
      expect(Notification.count).to eq(Achievement.count)
    end

    it "calls ShinyUnlocked.report! in ascending-threshold order" do
      emitted_thresholds = []
      allow(Pito::Notifications::Source::ShinyUnlocked).to receive(:report!) do |achievement|
        emitted_thresholds << achievement.threshold
      end

      job.perform

      expect(emitted_thresholds).not_to be_empty
      expect(emitted_thresholds).to eq(emitted_thresholds.sort)
    end

    it "creates no notifications on a second run when nothing new is unlocked" do
      job.perform
      expect { job.perform }.not_to change(Notification, :count)
    end
  end

  # ─── skips needs_reauth channels ────────────────────────────────────────────

  describe "skipping needs_reauth channels" do
    let(:reauth_connection) { create(:youtube_connection, :needs_reauth) }
    let!(:reauth_channel) do
      create(:channel, youtube_connection: reauth_connection, youtube_channel_id: "UCreauth")
    end
    let!(:reauth_video) { create(:video, channel: reauth_channel, youtube_video_id: "reauth_vid") }

    it "does not call top_videos for a needs_reauth channel" do
      reauth_analytics = instance_double(Channel::Youtube::AnalyticsClient)
      allow(Channel::Youtube::AnalyticsClient).to receive(:new).with(reauth_connection).and_return(reauth_analytics)
      expect(reauth_analytics).not_to receive(:top_videos)

      job.perform
    end

    it "does not write AchievementMetric rows for videos on a needs_reauth channel" do
      job.perform
      expect(AchievementMetric.where(achievable: reauth_video)).to be_empty
    end
  end

  # ─── no videos on channel ───────────────────────────────────────────────────

  describe "channel with no videos" do
    let(:empty_connection) { create(:youtube_connection) }
    let!(:empty_channel) do
      create(:channel, youtube_connection: empty_connection, youtube_channel_id: "UCempty")
    end

    let(:empty_analytics) { instance_double(Channel::Youtube::AnalyticsClient) }
    let(:empty_data)      { instance_double(Channel::Youtube::Client) }

    before do
      allow(Channel::Youtube::AnalyticsClient).to receive(:new).with(empty_connection).and_return(empty_analytics)
      allow(Channel::Youtube::Client).to receive(:new).with(empty_connection).and_return(empty_data)
      allow(empty_analytics).to receive(:top_videos).and_return([])
      allow(empty_data).to receive(:videos_list).and_return({ items: [] })
      allow(empty_data).to receive(:channels_list).and_return(
        { items: [ make_channel_item("UCempty", subscriber_count: "0") ] }
      )
    end

    it "does not raise" do
      expect { job.perform }.not_to raise_error
    end

    it "writes no video AchievementMetric rows for the empty channel" do
      job.perform
      # No videos exist on the empty channel, so no video rows
      video_achievable_ids = AchievementMetric
        .where(achievable_type: "Video")
        .pluck(:achievable_id)
      empty_video_ids = empty_channel.videos.pluck(:id)
      expect(video_achievable_ids & empty_video_ids).to be_empty
    end
  end
end
