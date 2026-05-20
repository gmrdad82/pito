require "rails_helper"

# Phase 26 — 01e. Daily digest scheduler — hourly cron tick.
RSpec.describe DailyDigestSchedulerJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The "daily digest is on" gate is
  # the shared `AppSetting.notifications_send_daily_digest?` flag AND at
  # least one `NotificationDeliveryChannel` with a present URL. The
  # per-brand `daily_digest` column was dropped.
  let!(:channel) do
    NotificationDeliveryChannel.create!(
      kind: "slack",
      webhook_url: "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567"
    )
  end

  before do
    AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
  end

  # `last_run` defaults to a clearly-in-the-past instant relative to
  # every `travel_to` target the spec uses (2026-01 / 2026-03 / 2026-06
  # / 2026-11). The real wall-clock at test time is later than these
  # but `2.days.ago` resolves to (current_real_time - 2d) which may
  # fall AFTER the travel target — that hits the 23h cooldown and
  # silently fails the pickup. Hard-pinning to a 2025 instant avoids
  # that trap.
  def with_user(tz:, last_run: Time.utc(2025, 1, 1, 0, 0, 0))
    user = create(:user, time_zone: tz, last_digest_run_at: last_run)
    user
  end

  # Returns the list of user_ids enqueued to DailyDigestDeliverJob in
  # the current example. ActiveJob's TestHelper stores jobs in
  # `enqueued_jobs` (an Array of Hash). Filtering by class isolates
  # this job from any other jobs the perform might enqueue.
  def enqueued_user_ids
    enqueued_jobs
      .select { |j| j[:job] == DailyDigestDeliverJob || j["job_class"] == "DailyDigestDeliverJob" }
      .map { |j| (j[:args] || j["arguments"]).first }
  end

  describe "pickup window — Etc/UTC user" do
    let!(:user) { with_user(tz: "Etc/UTC") }

    it "picks the user at the 09:00 UTC tick" do
      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end

    it "does NOT pick the user at the 08:00 UTC tick" do
      travel_to(Time.utc(2026, 6, 15, 8, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end

    it "does NOT pick the user at the 10:00 UTC tick" do
      travel_to(Time.utc(2026, 6, 15, 10, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end
  end

  describe "pickup window — Europe/Bucharest user" do
    let!(:user) { with_user(tz: "Europe/Bucharest") }

    it "picks at the 06:00 UTC tick in summer (EEST = UTC+3)" do
      # June 15 — DST active. Local 09:00 = 06:00 UTC.
      travel_to(Time.utc(2026, 6, 15, 6, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end

    it "picks at the 07:00 UTC tick in winter (EET = UTC+2)" do
      # January 15 — DST inactive. Local 09:00 = 07:00 UTC.
      travel_to(Time.utc(2026, 1, 15, 7, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end

    it "does NOT pick at the 07:00 UTC tick in summer (off by one hour)" do
      travel_to(Time.utc(2026, 6, 15, 7, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end
  end

  describe "pickup window — Pacific/Kiritimati user (UTC+14)" do
    let!(:user) { with_user(tz: "Pacific/Kiritimati") }

    it "picks at the 19:00 UTC tick (= 09:00 LINT next calendar day)" do
      # Local 09:00 on June 16 = 19:00 UTC on June 15.
      travel_to(Time.utc(2026, 6, 15, 19, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end

    it "does NOT pick at the 18:00 UTC tick" do
      travel_to(Time.utc(2026, 6, 15, 18, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end
  end

  describe "pickup window — Pacific/Pago_Pago user (UTC-11)" do
    let!(:user) { with_user(tz: "Pacific/Pago_Pago") }

    it "picks at the 20:00 UTC tick (= 09:00 SST same calendar day)" do
      travel_to(Time.utc(2026, 6, 15, 20, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end

    it "does NOT pick at the 19:00 UTC tick" do
      travel_to(Time.utc(2026, 6, 15, 19, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end
  end

  describe "pickup window — Asia/Kolkata user (UTC+5:30 half-hour offset)" do
    let!(:user) { with_user(tz: "Asia/Kolkata") }

    it "picks at the 04:00 UTC tick (= 09:30 IST)" do
      # Local 09:00 = 03:30 UTC. The 03:30 instant falls inside the
      # (03:00, 04:00] pickup window, so the 04:00 UTC tick picks it.
      travel_to(Time.utc(2026, 6, 15, 4, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end
  end

  describe "pickup window — Australia/Eucla user (UTC+8:45 quarter-hour offset)" do
    let!(:user) { with_user(tz: "Australia/Eucla") }

    it "picks at the 01:00 UTC tick (covers the 00:15 UTC local-09:00 instant)" do
      travel_to(Time.utc(2026, 6, 15, 1, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end
  end

  describe "DST spring-forward (America/New_York, 2026-03-08)" do
    let!(:user) { with_user(tz: "America/New_York") }

    it "picks the user once on the spring-forward day" do
      # March 8 2026: clocks jump 02:00 → 03:00 EST → EDT.
      # 09:00 local on Mar 8 = 13:00 UTC (EDT = UTC-4).
      travel_to(Time.utc(2026, 3, 8, 13, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end

    it "picks at the correct UTC tick the day AFTER spring-forward" do
      # March 9 2026: EDT in effect, 09:00 local = 13:00 UTC.
      travel_to(Time.utc(2026, 3, 9, 13, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end
  end

  describe "DST fall-back (America/New_York, 2026-11-01)" do
    let!(:user) { with_user(tz: "America/New_York") }

    it "fires once at the post-fall-back 09:00 local instant" do
      # Nov 1 2026: clocks fall 02:00 → 01:00 EDT → EST.
      # 09:00 EST = 14:00 UTC.
      travel_to(Time.utc(2026, 11, 1, 14, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end
  end

  describe "idempotence" do
    let!(:user) { with_user(tz: "Etc/UTC") }

    it "does not double-fire when the scheduler runs twice in the same hour" do
      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        described_class.new.perform
        described_class.new.perform
      end
      expect(enqueued_user_ids.count(user.id)).to eq(1)
    end

    it "stamps `last_digest_run_at` when it picks a user" do
      tick = Time.utc(2026, 6, 15, 9, 0, 0)
      travel_to(tick) { described_class.new.perform }
      expect(user.reload.last_digest_run_at).to be_within(1.second).of(tick)
    end

    it "skips users whose `last_digest_run_at` is inside the 23h cooldown" do
      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        user.update!(last_digest_run_at: 1.hour.ago)
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end
  end

  describe "users without enabled channels" do
    it "does NOT pick users when the shared daily-digest toggle is off" do
      AppSetting.set_notification_toggle!(:notifications_send_daily_digest, false)
      user = with_user(tz: "Etc/UTC")
      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end

    it "does NOT pick users when no NotificationDeliveryChannel has a URL" do
      channel.update!(webhook_url: nil)
      user = with_user(tz: "Etc/UTC")
      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end

    it "is a no-op when no users exist at all" do
      expect {
        travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
          described_class.new.perform
        end
      }.not_to raise_error
    end
  end

  # P26 reviewer concern 1 — locked decision: ONE digest per install
  # per day, regardless of user count. Multi-user installs share the
  # install-level webhook channels (ADR 0003 — no `user_id` on
  # `notification_delivery_channels`), so per-user fan-out would
  # N-fire into the same Slack/Discord channel.
  describe "install-level dispatch (multi-user)" do
    it "enqueues exactly one DailyDigestDeliverJob for the anchor user (lowest id) when multiple users exist" do
      anchor = with_user(tz: "Etc/UTC")
      _later1 = with_user(tz: "Etc/UTC")
      _later2 = with_user(tz: "Etc/UTC")

      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        described_class.new.perform
      end

      expect(enqueued_user_ids).to eq([ anchor.id ])
    end

    it "uses the anchor's tz (NOT a later user's tz) to decide pickup" do
      # Anchor = Etc/UTC → 09:00 UTC tick fires.
      # Second user = Europe/Bucharest → 06:00 UTC summer tick would fire
      # for them in isolation; the install-level dispatch ignores it.
      anchor = with_user(tz: "Etc/UTC")
      _bucharest = with_user(tz: "Europe/Bucharest")

      # 06:00 UTC summer — Bucharest local 09:00 in EEST, but the anchor
      # is on Etc/UTC so this is a 06:00 anchor-local instant, NOT 09:00.
      travel_to(Time.utc(2026, 6, 15, 6, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to be_empty

      # 09:00 UTC — anchor-local 09:00, fires.
      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to eq([ anchor.id ])
    end

    it "does NOT double-fire when many users would individually be ripe at the same tick" do
      anchor = with_user(tz: "Etc/UTC")
      _others = Array.new(3) { with_user(tz: "Etc/UTC") }

      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        described_class.new.perform
      end

      # One enqueued job total — for the anchor only.
      expect(enqueued_user_ids.count).to eq(1)
      expect(enqueued_user_ids.first).to eq(anchor.id)
    end
  end

  describe "edge: user enabled digest after today's 09:00 passed" do
    it "is not picked today (last_digest_run_at default == now)" do
      user = with_user(tz: "Etc/UTC", last_run: Time.utc(2026, 6, 15, 8, 30, 0))
      # 09:00 has passed (8:30 stamp = "just enabled"); cooldown blocks.
      travel_to(Time.utc(2026, 6, 15, 9, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).not_to include(user.id)
    end
  end

  describe "tz-change edge" do
    it "next tick picks the user based on the NEW tz after a change" do
      user = with_user(tz: "Etc/UTC")
      # User changes their tz to Bucharest (UTC+3 in June).
      user.update!(time_zone: "Europe/Bucharest")
      travel_to(Time.utc(2026, 6, 15, 6, 0, 0)) do
        described_class.new.perform
      end
      expect(enqueued_user_ids).to include(user.id)
    end
  end

  describe "Sidekiq cron registration" do
    it "is registered in config/sidekiq_cron.yml every hour at minute 0" do
      schedule_path = Rails.root.join("config", "sidekiq_cron.yml")
      cron = YAML.load_file(schedule_path)
      entry = cron["daily_digest_scheduler"]
      expect(entry).to be_present
      expect(entry["class"]).to eq("DailyDigestSchedulerJob")
      expect(entry["cron"]).to eq("0 * * * *")
    end
  end

  describe "claim atomicity" do
    it "does not double-fire on race between two simultaneous ticks" do
      user = with_user(tz: "Etc/UTC")
      tick = Time.utc(2026, 6, 15, 9, 0, 0)
      travel_to(tick) do
        # Simulate a race: both calls happen at the same instant.
        described_class.new.perform
        described_class.new.perform
      end
      expect(enqueued_user_ids.count(user.id)).to eq(1)
    end
  end
end
