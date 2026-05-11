require "rails_helper"

RSpec.describe Notification, type: :model do
  let(:calendar_entry) { create(:calendar_entry) }

  describe "validations" do
    it "is valid with a calendar entry source" do
      notif = build(:notification, source_calendar_entry: calendar_entry)
      expect(notif).to be_valid
    end

    it "is invalid without an event_type" do
      notif = build(:notification, event_type: nil)
      expect(notif).not_to be_valid
      expect(notif.errors[:event_type]).to include(/can't be blank/)
    end

    it "rejects event_type longer than 64 characters" do
      notif = build(:notification, event_type: "x" * 65)
      expect(notif).not_to be_valid
      expect(notif.errors[:event_type].any? { |m| m =~ /too long/i || m =~ /length/i }).to be(true)
    end

    it "accepts event_type at exactly 64 characters" do
      notif = build(:notification, event_type: "x" * 64)
      expect(notif).to be_valid
    end

    it "is invalid without a title" do
      notif = build(:notification, title: nil)
      expect(notif).not_to be_valid
      expect(notif.errors[:title]).to be_present
    end

    it "rejects titles longer than 255 characters" do
      notif = build(:notification, title: "x" * 256)
      expect(notif).not_to be_valid
    end

    it "accepts a title at exactly 255 characters" do
      notif = build(:notification, title: "x" * 255)
      expect(notif).to be_valid
    end

    it "rejects bodies longer than 5000 characters" do
      notif = build(:notification, body: "x" * 5001)
      expect(notif).not_to be_valid
      expect(notif.errors[:body]).to be_present
    end

    it "accepts a body at exactly 5000 characters" do
      notif = build(:notification, body: "x" * 5000)
      expect(notif).to be_valid
    end

    it "rejects URLs longer than 1000 characters" do
      notif = build(:notification, url: "https://example.com/" + ("x" * 1000))
      expect(notif).not_to be_valid
    end

    it "accepts a fully-qualified https URL" do
      notif = build(:notification, url: "https://pitomd.com/notifications/123")
      expect(notif).to be_valid
    end

    it "accepts a fully-qualified http URL" do
      notif = build(:notification, url: "http://localhost:3000/videos/1")
      expect(notif).to be_valid
    end

    it "accepts a leading-slash app path" do
      notif = build(:notification, url: "/videos/1")
      expect(notif).to be_valid
    end

    it "rejects a malformed URL" do
      notif = build(:notification, url: "not-a-url")
      expect(notif).not_to be_valid
      expect(notif.errors[:url]).to be_present
    end

    it "rejects a non-http scheme" do
      notif = build(:notification, url: "ftp://example.com/foo")
      expect(notif).not_to be_valid
    end

    # Phase 16 audit F1 — open-redirect class. The APP_PATH_PATTERN
    # accepts a leading slash but must reject a SECOND character that
    # is `/` or `\`, which would otherwise let `//evil.com/x` (a
    # protocol-relative URL) or `/\evil.com/x` (a backslash-bypass
    # variant some browsers normalize to `//evil.com/x`) smuggle an
    # external host past the validator.
    describe "URL open-redirect protection (F1)" do
      it "rejects a protocol-relative URL with leading double slash" do
        notif = build(:notification, url: "//evil.com/x")
        expect(notif).not_to be_valid
        expect(notif.errors[:url]).to be_present
      end

      it "rejects a backslash-bypass variant" do
        notif = build(:notification, url: "/\\evil.com/x")
        expect(notif).not_to be_valid
        expect(notif.errors[:url]).to be_present
      end

      it "rejects a leading double slash with no path tail" do
        notif = build(:notification, url: "//evil.com")
        expect(notif).not_to be_valid
        expect(notif.errors[:url]).to be_present
      end

      it "still accepts an interior double slash inside an app path" do
        notif = build(:notification, url: "/foo//bar")
        expect(notif).to be_valid
      end

      it "rejects javascript: scheme" do
        notif = build(:notification, url: "javascript:alert(1)")
        expect(notif).not_to be_valid
      end

      it "rejects data: scheme" do
        notif = build(:notification, url: "data:text/html,<script>1</script>")
        expect(notif).not_to be_valid
      end

      it "rejects vbscript: scheme" do
        notif = build(:notification, url: "vbscript:msgbox(1)")
        expect(notif).not_to be_valid
      end

      it "rejects file: scheme" do
        notif = build(:notification, url: "file:///etc/passwd")
        expect(notif).not_to be_valid
      end
    end

    it "is invalid without fires_at" do
      notif = build(:notification, fires_at: nil)
      expect(notif).not_to be_valid
      expect(notif.errors[:fires_at]).to be_present
    end

    it "rejects last_error longer than 1000 characters" do
      notif = build(:notification, last_error: "x" * 1001)
      expect(notif).not_to be_valid
    end

    describe "idempotency keys" do
      it "rejects a row with neither source_calendar_entry_id NOR dedup_key" do
        notif = build(:notification, with_calendar_entry: false, dedup_key: nil)
        expect(notif).not_to be_valid
        expect(notif.errors[:base]).to include(/source_calendar_entry_id|dedup_key/)
      end

      it "accepts a row with source_calendar_entry_id only" do
        notif = build(:notification, source_calendar_entry: calendar_entry, dedup_key: nil)
        expect(notif).to be_valid
      end

      it "accepts a row with dedup_key only" do
        notif = build(:notification, with_calendar_entry: false, dedup_key: "k1")
        expect(notif).to be_valid
      end

      it "accepts a row with both source_calendar_entry_id AND dedup_key" do
        notif = build(:notification,
                      source_calendar_entry: calendar_entry,
                      dedup_key: "k1")
        expect(notif).to be_valid
      end
    end
  end

  describe "enums" do
    it "exposes every notification kind" do
      # Phase 22 adds `import_job_completed` for the `[import]` modal;
      # `video_diff_detected` may also be present once the daily diff
      # cron spec lands. We assert membership for the baseline kinds
      # rather than an exact match, to avoid coupling unrelated phase
      # work to this assertion.
      baseline = %w[
        video_published
        video_pre_publish_check_missed
        game_release_upcoming
        game_release_today
        milestone_reached
        calendar_entry_firing
        sync_error
        youtube_reauth_needed
        import_job_completed
      ]
      expect(Notification.kinds.keys).to include(*baseline)
    end

    it "exposes the four severities" do
      expect(Notification.severities.keys).to match_array(%w[info success warn urgent])
    end
  end

  describe "scopes" do
    let!(:unread1) { create(:notification, in_app_read_at: nil) }
    let!(:unread2) { create(:notification, in_app_read_at: nil) }
    let!(:read1)   { create(:notification, in_app_read_at: 1.hour.ago) }

    it "unread returns rows where in_app_read_at IS NULL only" do
      expect(Notification.unread).to match_array([ unread1, unread2 ])
    end

    it "read returns rows where in_app_read_at IS NOT NULL only" do
      expect(Notification.read).to match_array([ read1 ])
    end

    it "recent orders by created_at DESC" do
      ordered = [ unread1, unread2, read1 ].sort_by(&:created_at).reverse
      expect(Notification.recent.to_a).to eq(ordered)
    end

    it "by_kind filters correctly" do
      sync = create(:notification, :sync_error)
      expect(Notification.by_kind(:sync_error)).to include(sync)
      expect(Notification.by_kind(:sync_error)).not_to include(unread1)
    end

    it "ripe_for_delivery returns rows whose fires_at <= now" do
      past = create(:notification, fires_at: 1.minute.ago)
      future = create(:notification, fires_at: 1.hour.from_now)
      expect(Notification.ripe_for_delivery).to include(past)
      expect(Notification.ripe_for_delivery).not_to include(future)
    end

    it "pending_discord excludes rows with a stamped discord_delivered_at" do
      delivered = create(:notification, :discord_delivered)
      pending = create(:notification)
      expect(Notification.pending_discord).to include(pending)
      expect(Notification.pending_discord).not_to include(delivered)
    end

    it "pending_slack excludes rows with a stamped slack_delivered_at" do
      delivered = create(:notification, :slack_delivered)
      pending = create(:notification)
      expect(Notification.pending_slack).to include(pending)
      expect(Notification.pending_slack).not_to include(delivered)
    end
  end

  describe "state methods" do
    let(:notif) { create(:notification) }

    it "mark_read! stamps in_app_read_at" do
      expect { notif.mark_read! }.to change { notif.reload.in_app_read_at }.from(nil)
    end

    it "mark_read!(at:) accepts an explicit timestamp" do
      ts = Time.zone.parse("2026-01-15 12:00:00 UTC")
      notif.mark_read!(at: ts)
      expect(notif.reload.in_app_read_at).to be_within(1.second).of(ts)
    end

    it "mark_unread! clears in_app_read_at" do
      notif.update!(in_app_read_at: 1.hour.ago)
      expect { notif.mark_unread! }.to change { notif.reload.in_app_read_at }.to(nil)
    end

    it "read? reflects the column" do
      expect(notif.read?).to be(false)
      notif.update!(in_app_read_at: Time.current)
      expect(notif.read?).to be(true)
    end

    it "unread? reflects the column" do
      expect(notif.unread?).to be(true)
      notif.update!(in_app_read_at: Time.current)
      expect(notif.unread?).to be(false)
    end
  end

  describe "idempotency at the DB layer" do
    it "rejects a duplicate (event_type, source_calendar_entry_id, fires_at)" do
      ts = 1.hour.from_now
      Notification.create!(
        kind: :game_release_upcoming, event_type: "game_release_upcoming",
        title: "x", severity: :info, fires_at: ts,
        source_calendar_entry: calendar_entry
      )
      expect {
        Notification.create!(
          kind: :game_release_upcoming, event_type: "game_release_upcoming",
          title: "y", severity: :info, fires_at: ts,
          source_calendar_entry: calendar_entry
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a duplicate (event_type, dedup_key)" do
      Notification.create!(
        kind: :sync_error, event_type: "sync_error",
        title: "x", severity: :urgent, fires_at: Time.current,
        dedup_key: "k1"
      )
      expect {
        Notification.create!(
          kind: :sync_error, event_type: "sync_error",
          title: "y", severity: :urgent, fires_at: Time.current,
          dedup_key: "k1"
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "enforces the CHECK constraint at the DB layer for direct SQL" do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO notifications
            (kind, event_type, severity, title, fires_at, retry_count,
             event_payload, created_at, updated_at)
          VALUES (0, 'video_published', 0, 't', NOW(), 0, '{}', NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /idempotency_keys_present/)
    end
  end

  describe "edge cases" do
    it "event_payload defaults to {}" do
      notif = build(:notification, event_payload: nil)
      # ActiveRecord respects the schema default; an explicitly nil
      # event_payload is treated as "use default" when persisted.
      n = Notification.new(
        kind: :calendar_entry_firing, event_type: "calendar_entry_firing",
        title: "x", severity: :info, fires_at: Time.current,
        source_calendar_entry: calendar_entry
      )
      n.save!
      expect(n.reload.event_payload).to eq({})
    end

    it "retry_count defaults to 0" do
      n = create(:notification)
      expect(n.retry_count).to eq(0)
    end

    it "severity defaults to :info" do
      n = Notification.new(
        kind: :calendar_entry_firing, event_type: "calendar_entry_firing",
        title: "x", fires_at: Time.current,
        source_calendar_entry: calendar_entry
      )
      n.save!
      expect(n.reload.info?).to be(true)
    end

    it "resolves source_calendar_entry association" do
      n = create(:notification, source_calendar_entry: calendar_entry)
      expect(n.source_calendar_entry).to eq(calendar_entry)
    end

    it "resolves source_milestone_rule association" do
      rule = create(:milestone_rule)
      n = create(:notification, source_milestone_rule: rule)
      expect(n.source_milestone_rule).to eq(rule)
    end

    it "resolves created_by_user association" do
      user = create(:user)
      n = create(:notification, created_by_user: user)
      expect(n.created_by_user).to eq(user)
    end

    it "source_calendar_entry deletion cascades and removes the notification" do
      # Phase 16 audit F4 — the original `:nullify` FK conflicted with
      # the CHECK (`source_calendar_entry_id IS NOT NULL OR dedup_key
      # IS NOT NULL`): a calendar-derived row with no `dedup_key` would
      # raise on parent delete. Resolution: `:cascade`. Notifications
      # tied to a calendar entry die with their source.
      entry = create(:calendar_entry)
      n = create(:notification, source_calendar_entry: entry, dedup_key: nil)
      expect { entry.destroy }.not_to raise_error
      expect(Notification.exists?(n.id)).to be(false)
    end

    it "source_calendar_entry deletion still cascades when dedup_key is present" do
      # Even rows that carry both keys cascade — calendar-derived
      # lifecycle wins regardless of the auxiliary dedup_key.
      entry = create(:calendar_entry)
      n = create(:notification, source_calendar_entry: entry,
                                dedup_key: "fk-cascade-test-#{SecureRandom.hex(4)}")
      expect { entry.destroy }.not_to raise_error
      expect(Notification.exists?(n.id)).to be(false)
    end

    it "source_milestone_rule deletion sets the FK to NULL" do
      rule = create(:milestone_rule)
      n = create(:notification, source_milestone_rule: rule,
                                source_calendar_entry: calendar_entry)
      rule.destroy
      expect(Notification.exists?(n.id)).to be(true)
      expect(n.reload.source_milestone_rule_id).to be_nil
    end

    it "created_by_user deletion sets the FK to NULL" do
      user = create(:user)
      n = create(:notification, created_by_user: user)
      user.destroy
      expect(Notification.exists?(n.id)).to be(true)
      expect(n.reload.created_by_user_id).to be_nil
    end
  end

  describe "flaw tests" do
    it "stores a script tag in title verbatim (UI escapes elsewhere)" do
      n = create(:notification, title: "<script>alert('x')</script>")
      expect(n.reload.title).to eq("<script>alert('x')</script>")
    end

    it "stores a unicode title verbatim" do
      title = "🎉 milestone — 100k subs ‫RTL‬"
      n = create(:notification, title: title)
      expect(n.reload.title).to eq(title)
    end

    it "scope queries on a 1000-row inbox stay fast" do
      now = Time.current
      rows = 1000.times.map do |i|
        {
          kind: 0,
          event_type: "video_published",
          severity: 0,
          title: "row #{i}",
          # No source_calendar_entry_id — uniqueness is on dedup_key only.
          fires_at: now,
          retry_count: 0,
          event_payload: {},
          dedup_key: "smoke-#{i}",
          created_at: now,
          updated_at: now
        }
      end
      Notification.insert_all!(rows)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      count = Notification.unread.count
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect(count).to be >= 1000
      expect(elapsed).to be < 1.0
    end

    it "rejects a body of 5001 chars and accepts 4999 chars" do
      ok = build(:notification, body: "x" * 4999)
      bad = build(:notification, body: "x" * 5001)
      expect(ok).to be_valid
      expect(bad).not_to be_valid
    end
  end

  describe "no per-user filter on the model" do
    # Q1 — single shared inbox; the model must NOT carry a hidden
    # per-user scope. `unread` / `read` / `recent` operate on the row
    # globally. Verifying via the SQL of the default scope.
    it "has no default scope filtering by user" do
      sql = Notification.all.to_sql
      expect(sql).not_to include("user_id")
      expect(sql).not_to include("created_by_user_id")
    end
  end
end
