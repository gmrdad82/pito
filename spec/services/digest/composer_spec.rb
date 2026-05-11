require "rails_helper"

# Phase 26 — 01e. Composer aggregates the last 24h of pito activity
# into a provider-agnostic `Result` struct. Renderers
# (`Digest::SlackRenderer`, `Digest::DiscordRenderer`) consume the
# Result and shape it for their wire format.
RSpec.describe ::Digest::Composer do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:now) { Time.utc(2026, 6, 15, 12, 0, 0) }
  subject(:result) { described_class.new(user, now: now).call }

  describe "the result envelope" do
    it "stamps the 24h window endpoints" do
      expect(result.window_started_at).to eq(now - 24.hours)
      expect(result.window_ended_at).to eq(now)
    end

    it "carries the user" do
      expect(result.user).to eq(user)
    end

    it "exposes every section in `#sections`" do
      labels = result.sections.map(&:label)
      expect(labels).to include(
        "channels synced",
        "videos imported",
        "videos updated",
        "footage imported",
        "login attempts",
        "open notifications"
      )
    end

    it "reports `any_activity? = false` when no activity inside the window" do
      expect(result.any_activity?).to be(false)
    end
  end

  describe "channels synced" do
    it "picks channels whose last_synced_at is inside the window" do
      inside = create(:channel, last_synced_at: now - 1.hour, title: "in-window channel")
      outside = create(:channel, last_synced_at: now - 25.hours, title: "out-of-window")
      expect(result.channels_synced.items).to include("in-window channel")
      expect(result.channels_synced.items).not_to include("out-of-window")
      expect(result.channels_synced.total).to eq(1)
      _ = outside
    end

    it "skips channels with NULL last_synced_at" do
      create(:channel, last_synced_at: nil, title: "never synced")
      expect(result.channels_synced.total).to eq(0)
    end

    it "caps the item list at SECTION_LIMIT and reports the true total" do
      # Stagger from `now - 1.minute` so every row lands strictly inside
      # the half-open `[start, now)` window.
      15.times { |i| create(:channel, last_synced_at: now - (i + 1).minutes, title: "ch-#{i}") }
      expect(result.channels_synced.items.size).to eq(described_class::SECTION_LIMIT)
      expect(result.channels_synced.total).to eq(15)
    end

    it "falls back to the handle when title is blank" do
      create(:channel, last_synced_at: now - 1.hour, title: nil, handle: "@user")
      expect(result.channels_synced.items).to include("@user")
    end
  end

  describe "videos imported" do
    let(:channel) { create(:channel) }

    it "picks videos created inside the window" do
      v = travel_to(now - 2.hours) { create(:video, channel: channel, title: "new vid") }
      expect(result.videos_imported.items).to include("new vid")
      _ = v
    end

    it "excludes videos created before the window" do
      travel_to(now - 30.hours) { create(:video, channel: channel, title: "old vid") }
      expect(result.videos_imported.items).not_to include("old vid")
    end
  end

  describe "videos updated" do
    let(:channel) { create(:channel) }

    it "picks videos re-synced in the window but created before it" do
      v = travel_to(now - 30.hours) { create(:video, channel: channel, title: "old vid") }
      v.update!(last_synced_at: now - 1.hour)
      expect(result.videos_updated.items).to include("old vid")
    end

    it "does NOT double-count a fresh import as 'updated'" do
      v = travel_to(now - 2.hours) { create(:video, channel: channel, title: "fresh vid") }
      v.update!(last_synced_at: now - 1.hour)
      expect(result.videos_updated.items).not_to include("fresh vid")
      expect(result.videos_imported.items).to include("fresh vid")
    end
  end

  describe "footage imported" do
    it "picks footage rows created inside the window" do
      project = create(:project)
      f = travel_to(now - 1.hour) { create(:footage, project: project, filename: "clip-A.mp4") }
      expect(result.footage_imported.items).to include("clip-A.mp4")
      _ = f
    end
  end

  describe "login attempts" do
    it "picks attempts created inside the window" do
      la = travel_to(now - 2.hours) do
        create(:login_attempt, result: :failed, email_attempted: "x@y.test")
      end
      expect(result.login_attempts.items.first).to include("failed")
      expect(result.login_attempts.items.first).to include("x@y.test")
      _ = la
    end

    it "excludes attempts created before the window" do
      travel_to(now - 30.hours) do
        create(:login_attempt, result: :failed, email_attempted: "old@y.test")
      end
      expect(result.login_attempts.items).to be_empty
    end
  end

  describe "open notifications" do
    it "picks unread notifications older than 1 hour" do
      n = travel_to(now - 2.hours) { create(:notification, :video_published, title: "old unread") }
      expect(result.notifications_open.items).to include("old unread")
      _ = n
    end

    it "excludes notifications younger than 1 hour to avoid flapping" do
      n = travel_to(now - 30.minutes) { create(:notification, :video_published, title: "fresh unread") }
      expect(result.notifications_open.items).not_to include("fresh unread")
      _ = n
    end

    it "excludes read notifications" do
      n = travel_to(now - 2.hours) { create(:notification, :read, :video_published, title: "old read") }
      expect(result.notifications_open.items).not_to include("old read")
      _ = n
    end
  end

  describe "`any_activity?`" do
    it "returns true once any section has at least one item" do
      create(:channel, last_synced_at: now - 1.hour)
      expect(result.any_activity?).to be(true)
    end

    it "returns false when every section is empty" do
      expect(result.any_activity?).to be(false)
    end
  end

  describe "Section struct" do
    it "exposes `empty?` aligned to a zero total" do
      sec = described_class::Section.new(label: "x", total: 0, items: [])
      expect(sec.empty?).to be(true)
      sec = described_class::Section.new(label: "x", total: 3, items: %w[a b c])
      expect(sec.empty?).to be(false)
    end
  end
end
