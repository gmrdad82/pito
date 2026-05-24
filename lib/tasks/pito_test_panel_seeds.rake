# Phase 5 (2026-05-24). Per-panel dev/test rake tasks that seed real
# rows AND broadcast a cable update on the relevant `pito:home:<panel>`
# stream so the live UI (when the consuming panel ships content) updates
# without a refresh.
#
# Five surfaces — one per home panel that visualizes time-anchored data:
#
#   `pito:test:notification[type,severity,title]`
#     → Notification row + cable broadcast on `pito:home:notifications_feed`.
#
#   `pito:test:calendar_entry[type,offset_days]`
#     → CalendarEntry row at `now + offset.days` + cable broadcast on
#       `pito:home:calendar`.
#
#   `pito:test:channel_milestone[channel,kind,value]`
#     → MilestoneRule fire path (synthesized): Notification +
#       CalendarEntry pair + broadcast on BOTH `pito:home:notifications_feed`
#       AND `pito:home:calendar` (a single milestone surfaces on both).
#
#   `pito:test:session_login[device,browser,ip]`
#     → Session row for the first User + cable broadcast on
#       `pito:home:security`.
#
#   `pito:test:system_event[kind]`
#     → No DB write; cable broadcast on `pito:home:notifications_feed`
#       describing a system-level event (`retry_queue`, `dead_queue`,
#       `storage`, `log_files`).
#
# `pito:test:clear_panel_seeds` removes test-seeded rows. Identification
# convention: every test-created row carries a `dedup_key` (Notification)
# or `source_ref.test_seed` marker (CalendarEntry) starting with the
# `TEST_SEED_PREFIX` constant. Sessions are matched by a `user_agent`
# prefix `"pito:test:"` so a real login is never deleted.
#
# Sibling file `pito_test_broadcast.rake` keeps the no-DB synthetic
# broadcast surface (`pito:test:broadcast_sidekiq`,
# `pito:test:broadcast_notifications`) and the Sidekiq-state seed jobs.
# This file is the DB-touching counterpart; the two are intentionally
# split so a `clear` invocation targets the right surface.
namespace :pito do
  namespace :test do
    # Shared test-seed marker. Every row created here carries this
    # string in its `dedup_key` (notifications), `source_ref.test_seed`
    # (calendar_entries), or `user_agent` prefix (sessions). The
    # `clear_panel_seeds` task uses the same prefix to identify and
    # delete the rows it seeded.
    TEST_SEED_PREFIX = "pito:test:".freeze

    NOTIFICATIONS_PANEL_CHANNEL = "pito:home:notifications_feed".freeze
    CALENDAR_PANEL_CHANNEL      = "pito:home:calendar".freeze
    SECURITY_PANEL_CHANNEL      = "pito:home:security".freeze

    # Default enum values used when callers omit positional args. Kept
    # in one place so a future enum addition / rename is a one-line
    # change.
    DEFAULT_NOTIFICATION_KIND     = "video_published".freeze
    DEFAULT_NOTIFICATION_SEVERITY = "info".freeze
    DEFAULT_CALENDAR_ENTRY_TYPE   = "custom".freeze
    DEFAULT_MILESTONE_KIND        = "subscriber_count".freeze
    DEFAULT_SYSTEM_EVENT_KIND     = "retry_queue".freeze

    desc "synthesize a notification (creates Notification + broadcasts on pito:home:notifications_feed)"
    task :notification, [ :type, :severity, :title ] => :environment do |_t, args|
      kind     = (args[:type] || DEFAULT_NOTIFICATION_KIND).to_s
      severity = (args[:severity] || DEFAULT_NOTIFICATION_SEVERITY).to_s
      title    = (args[:title] ||
                  "test notification at #{Time.current.strftime('%H:%M:%S')}").to_s

      unless Notification.kinds.key?(kind)
        abort "[pito:test:notification] unknown kind=#{kind.inspect} (valid: #{Notification.kinds.keys.sort.join(', ')})"
      end
      unless Notification.severities.key?(severity)
        abort "[pito:test:notification] unknown severity=#{severity.inspect} (valid: #{Notification.severities.keys.sort.join(', ')})"
      end

      dedup_key = "#{TEST_SEED_PREFIX}notification:#{SecureRandom.hex(8)}"
      notification = Notification.create!(
        kind: kind,
        severity: severity,
        title: title,
        body: nil,
        url: nil,
        event_type: kind,
        event_payload: { "test_seed" => true },
        dedup_key: dedup_key,
        fires_at: Time.current
      )

      Pito::CableBroadcaster.broadcast_panel(
        NOTIFICATIONS_PANEL_CHANNEL,
        kind: :notification_created,
        payload: { id: notification.id, kind: kind, severity: severity, title: title }
      )

      puts "[pito:test:notification] id=#{notification.id} kind=#{kind} severity=#{severity} title=#{title.inspect}"
    end

    desc "synthesize a calendar entry at now+offset_days (creates CalendarEntry + broadcasts on pito:home:calendar)"
    task :calendar_entry, [ :type, :offset_days ] => :environment do |_t, args|
      entry_type  = (args[:type] || DEFAULT_CALENDAR_ENTRY_TYPE).to_s
      offset_days = (args[:offset_days] || 0).to_i

      unless CalendarEntry.entry_types.key?(entry_type)
        abort "[pito:test:calendar_entry] unknown type=#{entry_type.inspect} (valid: #{CalendarEntry.entry_types.keys.sort.join(', ')})"
      end

      starts_at = Time.current + offset_days.days
      tz = Rails.application.config.x.pito.timezone
      title = "test #{entry_type} at #{starts_at.strftime('%Y-%m-%d %H:%M')}"

      # Note: per-type metadata schemas (see
      # CalendarEntryMetadataValidator) strip unknown keys silently —
      # the `test_seed` marker lives in `source_ref` (unconstrained)
      # instead of `metadata`.
      entry = CalendarEntry.create!(
        entry_type: entry_type,
        source: :manual,
        state: :scheduled,
        title: title,
        starts_at: starts_at,
        all_day: false,
        timezone: tz,
        metadata: { "user_overrides" => {} },
        source_ref: { "test_seed" => "#{TEST_SEED_PREFIX}calendar_entry" }
      )

      Pito::CableBroadcaster.broadcast_panel(
        CALENDAR_PANEL_CHANNEL,
        kind: :calendar_entry_created,
        payload: {
          id: entry.id,
          entry_type: entry_type,
          starts_at: starts_at.iso8601,
          offset_days: offset_days
        }
      )

      puts "[pito:test:calendar_entry] id=#{entry.id} type=#{entry_type} starts_at=#{starts_at.iso8601} offset=#{offset_days}d"
    end

    desc "fire a synthetic channel milestone (Notification + CalendarEntry + broadcasts on both notifications_feed + calendar)"
    task :channel_milestone, [ :channel, :kind, :value ] => :environment do |_t, args|
      channel_arg = args[:channel]
      kind        = (args[:kind] || DEFAULT_MILESTONE_KIND).to_s
      value       = (args[:value] || 1_000).to_i

      channel =
        if channel_arg.present?
          Channel.find_by(id: channel_arg.to_i) ||
            Channel.find_by("title ILIKE ?", "%#{channel_arg}%")
        else
          Channel.first
        end

      if channel.nil?
        abort "[pito:test:channel_milestone] no channel found (arg=#{channel_arg.inspect}); seed a channel first or pass a known id/title"
      end

      tz = Rails.application.config.x.pito.timezone
      title = "milestone: #{channel.title} reached #{value} #{kind}"
      dedup_key = "#{TEST_SEED_PREFIX}milestone:#{channel.id}:#{kind}:#{SecureRandom.hex(8)}"

      result = ActiveRecord::Base.transaction do
        # `milestone_manual` forbids the typed `channel_id` FK (per
        # CalendarEntryCrossReferenceValidator) AND restricts metadata
        # keys to `user_overrides` (per CalendarEntryMetadataValidator).
        # All test-seed context (channel + kind + value) lives in
        # `source_ref`, which is unconstrained.
        entry = CalendarEntry.create!(
          entry_type: :milestone_manual,
          source: :manual,
          state: :occurred,
          title: title,
          starts_at: Time.current,
          all_day: false,
          timezone: tz,
          metadata: { "user_overrides" => {} },
          source_ref: {
            "test_seed" => "#{TEST_SEED_PREFIX}channel_milestone",
            "channel_id" => channel.id,
            "milestone_kind" => kind,
            "milestone_value" => value
          }
        )

        notification = Notification.create!(
          kind: :milestone_reached,
          severity: :success,
          title: title,
          body: "Channel #{channel.title} crossed #{value} #{kind}.",
          event_type: "milestone_reached",
          event_payload: {
            "test_seed" => true,
            "channel_id" => channel.id,
            "milestone_kind" => kind,
            "milestone_value" => value
          },
          dedup_key: dedup_key,
          fires_at: Time.current
        )

        { entry: entry, notification: notification }
      end

      Pito::CableBroadcaster.broadcast_panel(
        NOTIFICATIONS_PANEL_CHANNEL,
        kind: :milestone_reached,
        payload: {
          notification_id: result[:notification].id,
          channel_id: channel.id,
          milestone_kind: kind,
          milestone_value: value
        }
      )

      Pito::CableBroadcaster.broadcast_panel(
        CALENDAR_PANEL_CHANNEL,
        kind: :milestone_reached,
        payload: {
          calendar_entry_id: result[:entry].id,
          channel_id: channel.id,
          milestone_kind: kind,
          milestone_value: value
        }
      )

      puts "[pito:test:channel_milestone] channel=#{channel.title.inspect} kind=#{kind} value=#{value} " \
           "notification=#{result[:notification].id} calendar_entry=#{result[:entry].id}"
    end

    desc "simulate a new session login (creates Session for first User + broadcasts on pito:home:security)"
    task :session_login, [ :device, :browser, :ip ] => :environment do |_t, args|
      device  = (args[:device] || "Desktop").to_s
      browser = (args[:browser] || "Firefox").to_s
      ip      = (args[:ip] || "127.0.0.1").to_s

      user = User.order(:id).first
      if user.nil?
        abort "[pito:test:session_login] no User present; create one before invoking this task"
      end

      # Synthesize a user_agent string that (a) carries the
      # TEST_SEED_PREFIX so `clear_panel_seeds` can find the row, and
      # (b) doesn't trip the Pito::Formatter::UserAgent regex into
      # picking the wrong device/browser — we set the device/browser
      # columns explicitly post-create to honor the caller's args.
      synthetic_ua = "#{TEST_SEED_PREFIX}session_login device=#{device} browser=#{browser}"

      session, _plaintext = Session.create_for!(
        user: user,
        ip: ip,
        user_agent: synthetic_ua
      )
      session.update_columns(device: device, browser: browser)

      Pito::CableBroadcaster.broadcast_panel(
        SECURITY_PANEL_CHANNEL,
        kind: :session_created,
        payload: {
          id: session.id,
          device: device,
          browser: browser,
          ip: ip
        }
      )

      puts "[pito:test:session_login] id=#{session.id} user=#{user.id} device=#{device} browser=#{browser} ip=#{ip}"
    end

    desc "synthesize a system event (broadcasts on pito:home:notifications_feed; no DB write)"
    task :system_event, [ :kind ] => :environment do |_t, args|
      kind = (args[:kind] || DEFAULT_SYSTEM_EVENT_KIND).to_s
      valid = %w[retry_queue dead_queue storage log_files]
      unless valid.include?(kind)
        abort "[pito:test:system_event] unknown kind=#{kind.inspect} (valid: #{valid.join(', ')})"
      end

      Pito::CableBroadcaster.broadcast_panel(
        NOTIFICATIONS_PANEL_CHANNEL,
        kind: :system_event,
        payload: {
          event_kind: kind,
          test_seed: true,
          ts: Time.current.iso8601
        }
      )

      puts "[pito:test:system_event] kind=#{kind} broadcast=#{NOTIFICATIONS_PANEL_CHANNEL}"
    end

    desc "clear panel-seed rows (notifications + calendar_entries + sessions; test-seeded only)"
    task clear_panel_seeds: :environment do
      notifications_deleted = Notification
        .where("dedup_key LIKE ?", "#{TEST_SEED_PREFIX}%")
        .delete_all

      calendar_entries_deleted = CalendarEntry
        .where("source_ref ->> 'test_seed' LIKE ?", "#{TEST_SEED_PREFIX}%")
        .delete_all

      sessions_deleted = Session
        .where("user_agent LIKE ?", "#{TEST_SEED_PREFIX}%")
        .delete_all

      puts "[pito:test:clear_panel_seeds] notifications=#{notifications_deleted} " \
           "calendar_entries=#{calendar_entries_deleted} sessions=#{sessions_deleted}"
    end
  end
end
