require "rails_helper"

RSpec.describe VideoPublish, type: :job do
  let(:user) { User.first || create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) { create(:channel, youtube_connection: connection) }

  it "no-ops when video is missing" do
    expect { described_class.new.perform(99999, "public") }.not_to raise_error
  end

  it "no-ops when pre_publish is incomplete" do
    v = create(:video, channel: channel) # NOT pre_publish_complete
    described_class.new.perform(v.id, "public")
    expect(v.reload.privacy_private?).to be(true)
  end

  it "publishes a complete video" do
    v = create(:video, :pre_publish_complete, channel: channel,
                       title: "ok", category_id: "20")
    VideoSyncBack.jobs.clear
    described_class.new.perform(v.id, "public")
    expect(v.reload.privacy_public?).to be(true)
  end

  it "schedules with publish_at" do
    v = create(:video, :pre_publish_complete, channel: channel,
                       title: "ok", category_id: "20")
    future = 1.day.from_now
    described_class.new.perform(v.id, "scheduled", future.iso8601)
    v.reload
    expect(v.privacy_private?).to be(true)
    expect(v.publish_at).to be_within(2.seconds).of(future)
  end

  it "configures sidekiq retry to 3" do
    expect(described_class.sidekiq_options["retry"]).to eq(3)
  end

  # Phase 26 — 01h. Timezone wiring on the scheduled-publish path.
  # The job receives an absolute UTC instant — the controller has
  # already converted user-local picker input via
  # `ScheduledPublishHelper#parse_user_local_to_utc`. These specs
  # pin the contract: the firing instant is timezone-invariant; a
  # user changing tz between schedule and fire does NOT move the
  # stored UTC instant.
  describe "timezone wiring on the schedule path" do
    let(:user_bucharest) do
      u = create(:user)
      u.update!(time_zone: "Europe/Bucharest")
      u
    end
    let(:connection_bucharest) { create(:youtube_connection, user: user_bucharest) }
    let(:channel_bucharest) { create(:channel, youtube_connection: connection_bucharest) }

    it "stores the UTC instant verbatim regardless of channel owner's tz" do
      v = create(:video, :pre_publish_complete, channel: channel_bucharest,
                         title: "ok", category_id: "20")
      # 09:00 Europe/Bucharest (DST) == 06:00 UTC.
      utc_instant = Time.utc(2026, 6, 1, 6, 0, 0)
      described_class.new.perform(v.id, "scheduled", utc_instant.iso8601)
      expect(v.reload.publish_at.utc).to eq(utc_instant)
    end

    it "stores the same UTC instant when the channel owner is in LA" do
      user_la = create(:user)
      user_la.update!(time_zone: "America/Los_Angeles")
      conn = create(:youtube_connection, user: user_la)
      ch = create(:channel, youtube_connection: conn)

      v = create(:video, :pre_publish_complete, channel: ch,
                         title: "ok", category_id: "20")
      utc_instant = Time.utc(2026, 6, 1, 6, 0, 0)
      described_class.new.perform(v.id, "scheduled", utc_instant.iso8601)
      expect(v.reload.publish_at.utc).to eq(utc_instant)
    end

    it "stored UTC instant does not move when the user changes tz post-schedule" do
      v = create(:video, :pre_publish_complete, channel: channel_bucharest,
                         title: "ok", category_id: "20")
      utc_instant = Time.utc(2026, 6, 1, 6, 0, 0)
      described_class.new.perform(v.id, "scheduled", utc_instant.iso8601)
      stored_before = v.reload.publish_at.utc

      # The user moves to LA — the stored UTC instant must be
      # invariant.
      user_bucharest.update!(time_zone: "America/Los_Angeles")
      expect(v.reload.publish_at.utc).to eq(stored_before)
    end

    it "preserves an edge-zone UTC instant (Pacific/Kiritimati +14)" do
      user_k = create(:user)
      user_k.update!(time_zone: "Pacific/Kiritimati")
      conn = create(:youtube_connection, user: user_k)
      ch = create(:channel, youtube_connection: conn)

      v = create(:video, :pre_publish_complete, channel: ch,
                         title: "ok", category_id: "20")
      # 14:00 Kiritimati on 2026-06-01 == 00:00 UTC same day.
      utc_instant = Time.utc(2026, 6, 1, 0, 0, 0)
      described_class.new.perform(v.id, "scheduled", utc_instant.iso8601)
      expect(v.reload.publish_at.utc).to eq(utc_instant)
    end

    it "preserves a half-hour-offset UTC instant (Asia/Kolkata +5:30)" do
      user_k = create(:user)
      user_k.update!(time_zone: "Asia/Kolkata")
      conn = create(:youtube_connection, user: user_k)
      ch = create(:channel, youtube_connection: conn)

      v = create(:video, :pre_publish_complete, channel: ch,
                         title: "ok", category_id: "20")
      # 12:00 Kolkata == 06:30 UTC.
      utc_instant = Time.utc(2026, 6, 1, 6, 30, 0)
      described_class.new.perform(v.id, "scheduled", utc_instant.iso8601)
      expect(v.reload.publish_at.utc).to eq(utc_instant)
    end

    it "logs the user's time_zone for observability on the schedule path" do
      v = create(:video, :pre_publish_complete, channel: channel_bucharest,
                         title: "ok", category_id: "20")
      utc_instant = Time.utc(2026, 6, 1, 6, 0, 0)
      messages = []
      allow(Rails.logger).to receive(:info).and_wrap_original do |orig, msg|
        messages << msg.to_s
        orig.call(msg)
      end
      described_class.new.perform(v.id, "scheduled", utc_instant.iso8601)
      tz_lines = messages.select { |m| m.include?("VideoPublish video_id=") }
      expect(tz_lines).not_to be_empty
      expect(tz_lines.first).to include("time_zone=Europe/Bucharest")
      expect(tz_lines.first).to include("publish_at_utc=#{utc_instant.iso8601}")
    end

    it "does NOT log the time_zone line on the immediate-publish path" do
      v = create(:video, :pre_publish_complete, channel: channel_bucharest,
                         title: "ok", category_id: "20")
      messages = []
      allow(Rails.logger).to receive(:info).and_wrap_original do |orig, msg|
        messages << msg.to_s
        orig.call(msg)
      end
      described_class.new.perform(v.id, "public")
      tz_lines = messages.select { |m| m.include?("VideoPublish video_id=") }
      expect(tz_lines).to be_empty
    end
  end
end
