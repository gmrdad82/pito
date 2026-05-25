# pito:test:calendar — dev/test seed tasks for CalendarEntry rows.
#
# Purpose: populate the database with a realistic spread of CalendarEntry rows
# across all four categories (channel / game / system / manual) and broadcast
# each creation on the `pito:home:calendar` cable stream so the live Home
# panel updates without a page refresh.
#
# Tasks:
#   pito:test:calendar:seed   — create N fake entries (default N=30)
#   pito:test:calendar:reset  — destroy only test-seeded CalendarEntry rows
#
# Env vars (both tasks):
#   COUNT    — total entries to generate (default: 30)
#   DELAY    — seconds between each create+broadcast (default: 0)
#   CATEGORY — restrict to one category: channel | game | system | manual
#              (default: all four categories, round-robined)
#
# Test-seed identification: every row created here carries
# `source_ref["test_seed"]` starting with TEST_SEED_PREFIX so the reset task
# can identify and delete only these rows. Real derived/auto rows are never
# touched by reset.
#
# Entry-type distribution per category:
#   channel — channel_published, video_scheduled, channel_anniversary
#   game    — game_release, owned_release_imminent
#   system  — system_event
#   manual  — milestone_manual, custom
#
# Date spread strategy:
#   33% of entries → current month (random day within ±15 days of today)
#   33% of entries → next month (random day 16–45 days out)
#   34% of entries → next 7 days (so `owned_release_imminent` fires and the
#                    upcoming-releases shelf sees data)
#
# Cable: each entry is broadcast on `pito:home:calendar` with
# kind `calendar_entry_created` immediately after DB creation.
#
# Related: pito_test_panel_seeds.rake (single-entry calendar_entry task),
#          pito:test:calendar:reset mirrors pito:test:clear_panel_seeds
#          scope (calendar_entries only).

namespace :pito do
  namespace :test do
    namespace :calendar do
      # ── Shared constants ───────────────────────────────────────────────

      CALENDAR_TEST_SEED_PREFIX  = "pito:test:".freeze
      CALENDAR_PANEL_STREAM      = "pito:home:calendar".freeze

      # Per-category entry_type pools. Only types that pass model
      # validators without FK requirements are listed here (so the seed
      # task can create rows without needing real Video/Game/Channel rows).
      # channel_published and channel_anniversary allow an optional
      # channel_id but don't require one. game_release allows an optional
      # game_id but doesn't require one. video_scheduled / video_published
      # REQUIRE a video_id FK so they are excluded from the pool — they
      # belong to the single-entry task (`pito:test:calendar_entry`) where
      # the caller can pass a known video id.
      CATEGORY_ENTRY_TYPES = {
        channel: %w[channel_published channel_anniversary],
        game:    %w[game_release owned_release_imminent],
        system:  %w[system_event],
        manual:  %w[milestone_manual custom]
      }.freeze

      # ── Helpers (module-level procs to avoid reopening the namespace) ──

      # Returns a Time within the current calendar month, skewed within
      # ±15 days of today.
      WITHIN_CURRENT_MONTH = lambda {
        offset = rand(-15..15)
        Time.current + offset.days
      }

      # Returns a Time in the next calendar month (16–45 days out).
      WITHIN_NEXT_MONTH = lambda {
        offset = rand(16..45)
        Time.current + offset.days
      }

      # Returns a Time within the next 7 days (1–7 days out).
      WITHIN_NEXT_7_DAYS = lambda {
        offset = rand(1..7)
        Time.current + offset.days
      }

      # Selects a date bucket for index i out of total n.
      #   i % 3 == 0 → current month (~33%)
      #   i % 3 == 1 → next month    (~33%)
      #   i % 3 == 2 → next 7 days   (~34%)
      DATE_BUCKET = lambda { |i|
        case i % 3
        when 0 then WITHIN_CURRENT_MONTH.call
        when 1 then WITHIN_NEXT_MONTH.call
        else        WITHIN_NEXT_7_DAYS.call
        end
      }

      # ── pito:test:calendar:seed ────────────────────────────────────────

      desc <<~DESC
        Seed N CalendarEntry rows across all categories + broadcast each on pito:home:calendar.

        ENV vars:
          COUNT=30       number of entries to create (default: 30)
          DELAY=0        seconds to wait between creates (default: 0)
          CATEGORY=...   restrict to one category: channel | game | system | manual
      DESC
      task seed: :environment do
        count    = (ENV.fetch("COUNT", "30")).to_i
        delay    = (ENV.fetch("DELAY", "0")).to_f
        category = ENV["CATEGORY"]&.strip&.downcase

        valid_categories = CATEGORY_ENTRY_TYPES.keys.map(&:to_s)

        if category && !valid_categories.include?(category)
          abort "[pito:test:calendar:seed] unknown CATEGORY=#{category.inspect} " \
                "(valid: #{valid_categories.join(' | ')})"
        end

        tz = Rails.application.config.x.pito.timezone

        # Build the type pool — either one category or round-robin all.
        pool =
          if category
            CATEGORY_ENTRY_TYPES[category.to_sym]
          else
            # Interleave all categories so the DB ends up with a realistic
            # spread regardless of the COUNT value.
            CATEGORY_ENTRY_TYPES.values.flatten
          end

        created = 0
        skipped = 0

        count.times do |i|
          entry_type = pool[i % pool.size]
          starts_at  = DATE_BUCKET.call(i)
          seed_key   = "#{CALENDAR_TEST_SEED_PREFIX}calendar:seed:#{SecureRandom.hex(6)}"
          label      = starts_at.strftime("%Y-%m-%d")
          title      = "test #{entry_type} #{label}"

          # owned_release_imminent must fall within the next 7 days to
          # trigger the "imminent" UI signal. Override date bucket when
          # this type is selected so at least its own occurrences land in
          # the right window.
          starts_at = WITHIN_NEXT_7_DAYS.call if entry_type == "owned_release_imminent"

          entry = CalendarEntry.new(
            entry_type: entry_type,
            source: :manual,
            state: :scheduled,
            title: title,
            starts_at: starts_at,
            all_day: true,
            timezone: tz,
            metadata: { "user_overrides" => {} },
            source_ref: { "test_seed" => seed_key }
          )

          if entry.save
            Pito::CableBroadcaster.broadcast_panel(
              CALENDAR_PANEL_STREAM,
              kind: :calendar_entry_created,
              payload: {
                id:         entry.id,
                entry_type: entry_type,
                category:   entry.category.to_s,
                starts_at:  starts_at.iso8601,
                title:      title
              }
            )

            puts "[pito:test:calendar:seed] ##{i + 1} id=#{entry.id} " \
                 "type=#{entry_type} category=#{entry.category} " \
                 "starts_at=#{starts_at.to_date}"

            created += 1
            sleep delay if delay.positive?
          else
            puts "[pito:test:calendar:seed] SKIP ##{i + 1} type=#{entry_type} " \
                 "errors=#{entry.errors.full_messages.join('; ')}"
            skipped += 1
          end
        end

        puts ""
        puts "[pito:test:calendar:seed] done — created=#{created} skipped=#{skipped} total=#{count}"
      end

      # ── pito:test:calendar:reset ───────────────────────────────────────

      desc <<~DESC
        Destroy all CalendarEntry rows that were created by pito:test:calendar:seed.

        Identifies rows by source_ref["test_seed"] starting with "pito:test:calendar:seed:".
        Real rows (derived, auto, manual non-test) are never touched.
      DESC
      task reset: :environment do
        deleted = CalendarEntry
          .where("source_ref ->> 'test_seed' LIKE ?",
                 "#{CALENDAR_TEST_SEED_PREFIX}calendar:seed:%")
          .delete_all

        puts "[pito:test:calendar:reset] deleted=#{deleted} test-seed CalendarEntry rows"
      end
    end
  end
end
