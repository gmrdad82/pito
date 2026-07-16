# frozen_string_literal: true

require "rails_helper"

RSpec.describe AchievementsRefreshJob, type: :job do
  include ActiveJob::TestHelper

  # ─── helpers ────────────────────────────────────────────────────────────────

  # Build a minimal LifetimeVideoReport row (lifetime per-video analytics).
  def make_analytics_row(video_id, views: 1000, minutes: 6000, subs_gained: 5)
    {
      video_id:                  video_id,
      views:                     views,
      estimated_minutes_watched: minutes,
      subscribers_gained:        subs_gained,
      subscribers_lost:          0
    }
  end

  # Build a minimal VideoStatsReadThrough result entry (views/likes/comments).
  def make_video_stats(views: 0, likes: 50, comments: 10)
    { views: views, likes: likes, comments: comments }
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

  let(:data_client) { instance_double(Channel::Youtube::Client) }

  before do
    allow(::Channel::Youtube::LifetimeVideoReport).to receive(:rows_for)
      .with(channel: channel, max_age: described_class::LIFETIME_MAX_AGE)
      .and_return([ make_analytics_row("vid_aaa", views: 1200, minutes: 3600, subs_gained: 8) ])

    allow(::Channel::Youtube::VideoStatsReadThrough).to receive(:call)
      .with(channel: channel, max_age: described_class::VIDEO_STATS_MAX_AGE)
      .and_return({ "vid_aaa" => make_video_stats(likes: 40, comments: 12) })

    allow(Channel::Youtube::Client).to receive(:new).with(connection).and_return(data_client)
    allow(data_client).to receive(:channels_list).and_return(
      { items: [ make_channel_item("UCprimary", subscriber_count: "5000") ] }
    )
  end

  subject(:job) { described_class.new }

  # ─── lifetime report + read-through seam calls ──────────────────────────────

  describe "lifetime video report + video stats read-through seams" do
    it "calls LifetimeVideoReport.rows_for with the channel and the 12h max_age" do
      expect(::Channel::Youtube::LifetimeVideoReport).to receive(:rows_for)
        .with(channel: channel, max_age: 12.hours)
        .and_return([])

      job.perform
    end

    it "calls VideoStatsReadThrough.call with the channel and the 3h max_age" do
      expect(::Channel::Youtube::VideoStatsReadThrough).to receive(:call)
        .with(channel: channel, max_age: 3.hours)
        .and_return({})

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

    let(:data_client2) { instance_double(Channel::Youtube::Client) }

    before do
      allow(::Channel::Youtube::LifetimeVideoReport).to receive(:rows_for)
        .with(channel: channel2, max_age: described_class::LIFETIME_MAX_AGE)
        .and_return([ make_analytics_row("vid_bbb", views: 800, minutes: 1200, subs_gained: 3) ])

      allow(::Channel::Youtube::VideoStatsReadThrough).to receive(:call)
        .with(channel: channel2, max_age: described_class::VIDEO_STATS_MAX_AGE)
        .and_return({ "vid_bbb" => make_video_stats(likes: 20, comments: 5) })

      allow(Channel::Youtube::Client).to receive(:new).with(connection2).and_return(data_client2)
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

    let(:data_client2) { instance_double(Channel::Youtube::Client) }

    before do
      allow(Channel::Youtube::Client).to receive(:new).with(connection2).and_return(data_client2)

      # channel's lifetime report raises; channel2's succeeds
      allow(::Channel::Youtube::LifetimeVideoReport).to receive(:rows_for)
        .with(channel: channel, max_age: described_class::LIFETIME_MAX_AGE)
        .and_raise(StandardError, "analytics boom")

      allow(::Channel::Youtube::LifetimeVideoReport).to receive(:rows_for)
        .with(channel: channel2, max_age: described_class::LIFETIME_MAX_AGE)
        .and_return([ make_analytics_row("vid_bbb", views: 500, minutes: 600, subs_gained: 2) ])

      allow(::Channel::Youtube::VideoStatsReadThrough).to receive(:call)
        .with(channel: channel2, max_age: described_class::VIDEO_STATS_MAX_AGE)
        .and_return({ "vid_bbb" => make_video_stats(likes: 5, comments: 1) })

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

    # The owner's contract: the failure becomes an AppSignal incident AND
    # stays isolated — reported, never re-raised, siblings unaffected.
    it "reports the error to AppSignal without breaking isolation" do
      allow(Appsignal).to receive(:report_error)

      expect { job.perform }.not_to raise_error

      expect(Appsignal).to have_received(:report_error)
        .with(an_instance_of(StandardError).and(having_attributes(message: "analytics boom")))
      expect(AchievementMetric.find_by(achievable: video2, metric: "views")&.value).to eq(500)
    end

    it "still writes metrics for the channel that succeeded" do
      job.perform
      row = AchievementMetric.find_by(achievable: video2, metric: "views")
      expect(row&.value).to eq(500)
    end
  end

  # ─── channel subscriber count ────────────────────────────────────────────────

  describe "channel subscriber count" do
    context "when a fresh subscribers stat row exists" do
      before { ::Pito::Stats.set(channel, :subscribers, 7_500) }

      it "does not fetch from channels_list" do
        expect(Channel::Youtube::Client).not_to receive(:new)

        job.perform
      end

      it "uses the fresh stat row's value for the subs metric" do
        job.perform
        row = AchievementMetric.find_by(achievable: channel, metric: "subs")
        expect(row&.value).to eq(7_500)
      end
    end

    context "when the subscribers stat row is stale" do
      before do
        stat = ::Pito::Stats.set(channel, :subscribers, 1)
        stat.update!(synced_at: 13.hours.ago)
      end

      it "falls back to channels_list and persists the fetched value" do
        job.perform

        row = AchievementMetric.find_by(achievable: channel, metric: "subs")
        expect(row&.value).to eq(5000)

        stat_row = channel.stats.find_by(kind: "subscribers")
        expect(stat_row.value).to eq(5000)
      end
    end

    context "when the subscribers stat row is missing" do
      it "falls back to channels_list and persists the fetched value" do
        job.perform

        row = AchievementMetric.find_by(achievable: channel, metric: "subs")
        expect(row&.value).to eq(5000)

        stat_row = channel.stats.find_by(kind: "subscribers")
        expect(stat_row.value).to eq(5000)
      end
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

    it "does not enqueue an individual webhook delivery job per shiny (digested instead)" do
      expect { job.perform }.not_to have_enqueued_job(NotificationWebhookDeliverJob)
    end

    it "sends ONE WebhookDigest.call with a [witty, entity] row per unlocked shiny" do
      digest_calls = []
      allow(Pito::Notifications::WebhookDigest).to receive(:call) do |title:, accent:, rows:|
        digest_calls << { title: title, accent: accent, rows: rows }
      end

      job.perform

      expect(digest_calls.size).to eq(1)
      call = digest_calls.first
      expect(call[:title]).to eq("🏆 Achievements")
      expect(call[:accent]).to eq(Pito::Notifications::WebhookDigest::ACHIEVEMENTS)
      expect(call[:rows].size).to eq(Achievement.count)
      expect(call[:rows]).to all(be_an(Array).and(have_attributes(size: 2)))
    end

    it "still calls WebhookDigest.call (which no-ops) with empty rows on a run with no new unlocks" do
      job.perform

      expect(Pito::Notifications::WebhookDigest).to receive(:call).with(hash_including(rows: []))
      job.perform
    end
  end

  # ─── skips needs_reauth channels ────────────────────────────────────────────

  describe "skipping needs_reauth channels" do
    let(:reauth_connection) { create(:youtube_connection, :needs_reauth) }
    let!(:reauth_channel) do
      create(:channel, youtube_connection: reauth_connection, youtube_channel_id: "UCreauth")
    end
    let!(:reauth_video) { create(:video, channel: reauth_channel, youtube_video_id: "reauth_vid") }

    it "does not call LifetimeVideoReport.rows_for for a needs_reauth channel" do
      expect(::Channel::Youtube::LifetimeVideoReport).not_to receive(:rows_for)
        .with(channel: reauth_channel, max_age: anything)

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

    let(:empty_data) { instance_double(Channel::Youtube::Client) }

    before do
      allow(::Channel::Youtube::LifetimeVideoReport).to receive(:rows_for)
        .with(channel: empty_channel, max_age: described_class::LIFETIME_MAX_AGE)
        .and_return([])
      allow(::Channel::Youtube::VideoStatsReadThrough).to receive(:call)
        .with(channel: empty_channel, max_age: described_class::VIDEO_STATS_MAX_AGE)
        .and_return({})

      allow(Channel::Youtube::Client).to receive(:new).with(empty_connection).and_return(empty_data)
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
