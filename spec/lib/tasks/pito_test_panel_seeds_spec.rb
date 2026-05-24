# Phase 5 (2026-05-24). Lock the per-panel dev/test rake task contract:
#
#   pito:test:notification[type,severity,title]
#   pito:test:calendar_entry[type,offset_days]
#   pito:test:channel_milestone[channel,kind,value]
#   pito:test:session_login[device,browser,ip]
#   pito:test:system_event[kind]
#   pito:test:clear_panel_seeds
#
# Each task asserted on two surfaces:
#   1. The expected DB row is written with the test-seed marker so
#      `clear_panel_seeds` can find it.
#   2. The cable broadcast lands on the canonical
#      `pito:home:<panel>` channel via `Pito::CableBroadcaster.broadcast_panel`.
#
# The `clear_panel_seeds` task asserts that test-seeded rows are removed
# AND non-test rows are preserved (the most important contract — clearing
# must never delete real data).
require "rails_helper"
require "rake"

RSpec.describe "lib/tasks/pito_test_panel_seeds.rake" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/pito_test_panel_seeds",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  # Helper: silence rake `puts` output for cleaner test runs.
  def silence_stream(stream)
    old_stream = stream.dup
    stream.reopen(File::NULL)
    yield
  ensure
    stream.reopen(old_stream)
    old_stream.close
  end

  def execute(task_name, args_hash = {})
    task = Rake::Task[task_name]
    task.reenable
    arg_names = args_hash.keys
    arg_values = args_hash.values
    # Silence BOTH stdout (`puts` confirmations) and stderr (the
    # message `Kernel#abort` writes before raising SystemExit).
    silence_stream($stdout) do
      silence_stream($stderr) do
        task.execute(Rake::TaskArguments.new(arg_names, arg_values))
      end
    end
  end

  describe "pito:test:notification" do
    let(:task_name) { "pito:test:notification" }

    it "is defined" do
      expect(Rake::Task.task_defined?(task_name)).to be true
    end

    it "creates a Notification with the requested kind / severity / title and a test-seed dedup_key" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      expect {
        execute(task_name, type: "video_published", severity: "warn", title: "smoke")
      }.to change(Notification, :count).by(1)

      n = Notification.order(:id).last
      expect(n.kind).to eq("video_published")
      expect(n.severity).to eq("warn")
      expect(n.title).to eq("smoke")
      expect(n.event_type).to eq("video_published")
      expect(n.dedup_key).to start_with("pito:test:")
    end

    it "broadcasts on pito:home:notifications_feed with kind :notification_created" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_panel) do |channel, kind:, payload:|
        expect(channel).to eq("pito:home:notifications_feed")
        expect(kind).to eq(:notification_created)
        expect(payload).to include(:id, kind: "video_published", severity: "info")
      end

      execute(task_name, type: "video_published", severity: "info", title: "test")
    end

    it "defaults kind / severity / title when args are omitted" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      execute(task_name, type: nil, severity: nil, title: nil)
      n = Notification.order(:id).last
      expect(n.kind).to eq("video_published")
      expect(n.severity).to eq("info")
      expect(n.title).to match(/test notification at/)
    end

    it "aborts on an unknown kind without writing a row" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      expect {
        expect {
          execute(task_name, type: "nope_does_not_exist", severity: "info", title: "x")
        }.to raise_error(SystemExit)
      }.not_to change(Notification, :count)
    end
  end

  describe "pito:test:calendar_entry" do
    let(:task_name) { "pito:test:calendar_entry" }

    it "is defined" do
      expect(Rake::Task.task_defined?(task_name)).to be true
    end

    it "creates a CalendarEntry at now + offset_days with the test-seed marker in source_ref" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      expect {
        execute(task_name, type: "custom", offset_days: "3")
      }.to change(CalendarEntry, :count).by(1)

      entry = CalendarEntry.order(:id).last
      expect(entry.entry_type).to eq("custom")
      expect(entry.source).to eq("manual")
      expect(entry.state).to eq("scheduled")
      expect(entry.source_ref["test_seed"]).to start_with("pito:test:")
      expect(entry.starts_at).to be_within(1.hour).of(3.days.from_now)
    end

    it "broadcasts on pito:home:calendar with kind :calendar_entry_created" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_panel) do |channel, kind:, payload:|
        expect(channel).to eq("pito:home:calendar")
        expect(kind).to eq(:calendar_entry_created)
        expect(payload).to include(:id, :starts_at, entry_type: "custom", offset_days: 0)
      end

      execute(task_name, type: "custom", offset_days: "0")
    end

    it "aborts on an unknown entry_type without writing a row" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      expect {
        expect {
          execute(task_name, type: "nope_bad_type", offset_days: "0")
        }.to raise_error(SystemExit)
      }.not_to change(CalendarEntry, :count)
    end
  end

  describe "pito:test:channel_milestone" do
    let(:task_name) { "pito:test:channel_milestone" }
    let!(:channel) do
      # Channel URLs are validated against /UC[A-Za-z0-9_-]{22}/ — must
      # be exactly 24 chars total after the prefix. Pad SecureRandom
      # output to satisfy the regex deterministically.
      uc_suffix = SecureRandom.alphanumeric(22)
      Channel.create!(
        title: "Test Channel",
        channel_url: "https://www.youtube.com/channel/UC#{uc_suffix}"
      )
    end

    it "is defined" do
      expect(Rake::Task.task_defined?(task_name)).to be true
    end

    it "creates BOTH a Notification + a CalendarEntry tagged with the test-seed marker" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      expect {
        execute(task_name, channel: channel.id.to_s, kind: "subscriber_count", value: "5000")
      }.to change(Notification, :count).by(1)
       .and change(CalendarEntry, :count).by(1)

      n = Notification.order(:id).last
      expect(n.kind).to eq("milestone_reached")
      expect(n.severity).to eq("success")
      expect(n.dedup_key).to start_with("pito:test:milestone:")

      entry = CalendarEntry.order(:id).last
      expect(entry.entry_type).to eq("milestone_manual")
      # All test-seed context lives in `source_ref` (the
      # `milestone_manual` type forbids the typed `channel_id` FK AND
      # restricts metadata to `user_overrides`).
      expect(entry.source_ref["channel_id"]).to eq(channel.id)
      expect(entry.source_ref["test_seed"]).to start_with("pito:test:")
      expect(entry.source_ref["milestone_kind"]).to eq("subscriber_count")
      expect(entry.source_ref["milestone_value"]).to eq(5000)
    end

    it "broadcasts on BOTH pito:home:notifications_feed AND pito:home:calendar" do
      channels_seen = []
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel) do |channel, **|
        channels_seen << channel
      end

      execute(task_name, channel: channel.id.to_s, kind: "subscriber_count", value: "5000")
      expect(channels_seen).to contain_exactly("pito:home:notifications_feed", "pito:home:calendar")
    end

    it "aborts when no Channel matches the channel arg" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      expect {
        expect {
          execute(task_name, channel: "0", kind: "subscriber_count", value: "1000")
        }.to raise_error(SystemExit)
      }.not_to change(Notification, :count)
    end
  end

  describe "pito:test:session_login" do
    let(:task_name) { "pito:test:session_login" }
    # The task picks `User.order(:id).first` — guarantee one exists in
    # case the spec runs against an empty DB. If other rows exist
    # already, the task uses them; we assert the session attaches to
    # *some* user (the one the task chose), not to ours specifically.
    let!(:user) do
      User.create!(
        username: "tester_#{SecureRandom.hex(4)}",
        password: "test_password_123"
      )
    end

    it "is defined" do
      expect(Rake::Task.task_defined?(task_name)).to be true
    end

    it "creates a Session row tagged with the test-seed user_agent prefix" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      expect {
        execute(task_name, device: "Desktop", browser: "Chrome", ip: "10.0.0.1")
      }.to change(Session, :count).by(1)

      s = Session.order(:id).last
      expect(s.user_id).to eq(User.order(:id).first.id)
      expect(s.device).to eq("Desktop")
      expect(s.browser).to eq("Chrome")
      expect(s.user_agent).to start_with("pito:test:")
    end

    it "broadcasts on pito:home:security with kind :session_created" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_panel) do |channel, kind:, payload:|
        expect(channel).to eq("pito:home:security")
        expect(kind).to eq(:session_created)
        expect(payload).to include(:id, device: "Desktop", browser: "Chrome", ip: "10.0.0.1")
      end

      execute(task_name, device: "Desktop", browser: "Chrome", ip: "10.0.0.1")
    end
  end

  describe "pito:test:system_event" do
    let(:task_name) { "pito:test:system_event" }

    it "is defined" do
      expect(Rake::Task.task_defined?(task_name)).to be true
    end

    it "broadcasts on pito:home:notifications_feed with kind :system_event (no DB write)" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_panel) do |channel, kind:, payload:|
        expect(channel).to eq("pito:home:notifications_feed")
        expect(kind).to eq(:system_event)
        expect(payload).to include(event_kind: "storage", test_seed: true, ts: kind_of(String))
      end

      expect {
        execute(task_name, kind: "storage")
      }.not_to change(Notification, :count)
    end

    it "accepts each of the four system-event kinds (retry_queue, dead_queue, storage, log_files)" do
      %w[retry_queue dead_queue storage log_files].each do |k|
        captured = nil
        allow(Pito::CableBroadcaster).to receive(:broadcast_panel) do |_chan, kind:, payload:|
          captured = { kind: kind, payload: payload }
        end

        execute(task_name, kind: k)
        expect(captured[:kind]).to eq(:system_event)
        expect(captured[:payload][:event_kind]).to eq(k)
      end
    end

    it "aborts on an unknown kind" do
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)

      expect {
        execute(task_name, kind: "not_a_real_kind")
      }.to raise_error(SystemExit)
    end
  end

  describe "pito:test:clear_panel_seeds" do
    let(:task_name) { "pito:test:clear_panel_seeds" }
    let!(:user) do
      User.create!(
        username: "clearer_#{SecureRandom.hex(4)}",
        password: "test_password_123"
      )
    end

    it "is defined" do
      expect(Rake::Task.task_defined?(task_name)).to be true
    end

    it "deletes test-seeded notifications, calendar_entries, and sessions WITHOUT touching real rows" do
      # Seed three test rows via the task surface.
      allow(Pito::CableBroadcaster).to receive(:broadcast_panel)
      execute("pito:test:notification", type: "video_published", severity: "info", title: "x")
      execute("pito:test:calendar_entry", type: "custom", offset_days: "0")

      # Also create one real-ish row in each table that must SURVIVE
      # the clear pass.
      real_notification = Notification.create!(
        kind: :video_published,
        severity: :info,
        title: "real notification",
        event_type: "video_published",
        dedup_key: "real-not-a-test-seed-#{SecureRandom.hex(4)}",
        fires_at: Time.current
      )
      real_entry = CalendarEntry.create!(
        entry_type: :custom,
        source: :manual,
        state: :scheduled,
        title: "real calendar entry",
        starts_at: Time.current,
        timezone: "UTC",
        metadata: { "user_overrides" => {} }
      )
      real_session, _plain = Session.create_for!(
        user: user,
        ip: "192.168.1.1",
        user_agent: "Mozilla/5.0 real browser"
      )

      # Also create a test session.
      execute("pito:test:session_login", device: "Mobile", browser: "Safari", ip: "172.16.0.1")

      expect {
        execute(task_name)
      }.to change { Notification.where("dedup_key LIKE ?", "pito:test:%").count }.to(0)
       .and change { CalendarEntry.where("source_ref ->> 'test_seed' LIKE ?", "pito:test:%").count }.to(0)
       .and change { Session.where("user_agent LIKE ?", "pito:test:%").count }.to(0)

      # Real rows survive.
      expect(Notification.exists?(real_notification.id)).to be true
      expect(CalendarEntry.exists?(real_entry.id)).to be true
      expect(Session.exists?(real_session.id)).to be true
    end
  end
end
