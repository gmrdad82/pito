# pito:test:notifications — dev/test rake tasks for seeding Notification rows
# across all four categories (channel / game / system / manual) and broadcasting
# each row on `pito:home:notifications_feed` so the live NotificationsFeed panel
# updates incrementally without a page reload.
#
# Tasks
# -----
#   pito:test:notifications:seed
#     Creates N fake notifications spread across all four categories (or one
#     category when CATEGORY= is set). Default N=12 (3 per category). After each
#     insert the row is broadcast on `pito:home:notifications_feed` with
#     kind: "notification_created". A configurable delay (default 250 ms) is
#     inserted between creates so the UI can update incrementally.
#
#   pito:test:notifications:reset
#     Destroys ALL Notification rows unconditionally (hard reset for test state).
#
# Environment variables
# ----------------------
#   COUNT=N         Override total notification count (seed evenly across
#                   active categories; default 12).
#   DELAY=ms        Cadence between creates in milliseconds (default 250).
#   CATEGORY=name   Seed only one category: channel | game | system | manual.
#                   When set, COUNT applies to that single category only.
#
# Message corpus
# --------------
#   Messages are tweet-style (≤ 140 chars, no emojis) per the Builder contract.
#   The corpus is a static pool per category; the task samples from it so each
#   run produces a varied set without requiring real DB associations.
#
# Builder API used
#   Pito::Notifications::Builder.build_channel(channel:, ...)
#   Pito::Notifications::Builder.build_game(game:, ...)
#   Pito::Notifications::Builder.build_system(...)
#   Pito::Notifications::Builder.build_manual(user:, ...)
#
# Cable
#   Pito::CableBroadcaster.broadcast_panel("pito:home:notifications_feed", kind:, payload:)
#
# Related: lib/tasks/pito_test_panel_seeds.rake (single-row panel seeds),
#          app/services/pito/notifications/builder.rb
namespace :pito do
  namespace :test do
    namespace :notifications do
      NOTIFICATIONS_FEED_CHANNEL = "pito:home:notifications_feed".freeze

      # Static message corpus. Sampled cyclically per category so a
      # small COUNT still produces varied copy and a large COUNT repeats
      # the pool in order (Builder dedup_key includes a per-call digest so
      # repeats still produce distinct rows).
      CORPUS = {
        channel: [
          "channel hit 10k subs",
          "video 'Last of Us Part 1' crossed 100k views",
          "channel reached 50k watch hours this month",
          "video 'Hollow Knight' passed 25k views",
          "channel subscriber count grew 8% this week",
          "video 'Spider-Man 2' hit 500 likes"
        ].freeze,
        game: [
          "Hollow Knight: Silksong releases in 3 days",
          "Marvel's Wolverine added to library",
          "Black Myth: Wukong drops to lowest price",
          "Elden Ring DLC added to wishlist",
          "Baldur's Gate 3 new patch available",
          "Cyberpunk 2077 removed from wishlist"
        ].freeze,
        system: [
          "sidekiq has 12 retries — investigate",
          "log files > 250 MB — consider truncation",
          "meilisearch index lag above 30 seconds",
          "voyage AI quota at 85% — monitor usage",
          "postgres disk usage above 70%",
          "background jobs completed — queue clear"
        ].freeze,
        manual: [
          "Steam console release",
          "record new footage for Hollow Knight run",
          "update channel banner before weekend",
          "review pending video descriptions",
          "check affiliate links before publish",
          "audit playlist order for game series"
        ].freeze
      }.freeze

      # Kind mappings per category — valid Notification.kinds values.
      KIND_FOR_CATEGORY = {
        channel: :sync_error,
        game:    :game_release_today,
        system:  :import_job_completed,
        manual:  :calendar_entry_firing
      }.freeze

      SEVERITY_FOR_CATEGORY = {
        channel: :info,
        game:    :info,
        system:  :warn,
        manual:  :info
      }.freeze

      ALL_CATEGORIES = %i[channel game system manual].freeze

      desc "seed N fake notifications across all categories (COUNT=12, DELAY=250ms, CATEGORY=channel|game|system|manual)"
      task seed: :environment do
        total_count = (ENV["COUNT"] || 12).to_i
        delay_ms    = (ENV["DELAY"] || 250).to_i
        delay_s     = delay_ms / 1000.0

        raw_category = ENV["CATEGORY"]
        categories =
          if raw_category.present?
            sym = raw_category.strip.downcase.to_sym
            unless ALL_CATEGORIES.include?(sym)
              abort "[pito:test:notifications:seed] unknown CATEGORY=#{raw_category.inspect} " \
                    "(valid: #{ALL_CATEGORIES.join(', ')})"
            end
            [ sym ]
          else
            ALL_CATEGORIES
          end

        # Resolve records needed by channel / game / manual builders.
        # Bail early with a clear message if the DB isn't seeded enough.
        channel_record = Channel.order(:id).first
        game_record    = Game.order(:id).first
        user_record    = User.order(:id).first

        if categories.include?(:channel) && channel_record.nil?
          abort "[pito:test:notifications:seed] no Channel found — seed a channel first or use CATEGORY=game|system|manual"
        end
        if categories.include?(:game) && game_record.nil?
          abort "[pito:test:notifications:seed] no Game found — seed a game first or use CATEGORY=channel|system|manual"
        end
        if categories.include?(:manual) && user_record.nil?
          abort "[pito:test:notifications:seed] no User found — create a user first or use CATEGORY=channel|game|system"
        end

        # Distribute total_count as evenly as possible across active categories.
        # Extra items (when total_count is not divisible) go to earlier categories.
        per_category_base = total_count / categories.size
        remainder         = total_count % categories.size

        counts = categories.each_with_index.map do |_cat, idx|
          per_category_base + (idx < remainder ? 1 : 0)
        end

        category_counts = categories.zip(counts).to_h
        grand_total     = category_counts.values.sum

        puts "[pito:test:notifications:seed] creating #{grand_total} notification(s): " \
             "#{category_counts.map { |c, n| "#{c}=#{n}" }.join(' ')} delay=#{delay_ms}ms"

        created = 0
        failed  = 0

        category_counts.each do |category, n|
          corpus  = CORPUS[category]
          kind    = KIND_FOR_CATEGORY[category]
          severity = SEVERITY_FOR_CATEGORY[category]

          n.times do |i|
            message = corpus[i % corpus.size]

            result =
              case category
              when :channel
                Pito::Notifications::Builder.build_channel(
                  channel:  channel_record,
                  message:  message,
                  kind:     kind,
                  severity: severity
                )
              when :game
                Pito::Notifications::Builder.build_game(
                  game:     game_record,
                  message:  message,
                  kind:     kind,
                  severity: severity
                )
              when :system
                Pito::Notifications::Builder.build_system(
                  message:  message,
                  kind:     kind,
                  severity: severity
                )
              when :manual
                Pito::Notifications::Builder.build_manual(
                  user:     user_record,
                  message:  message,
                  kind:     kind,
                  severity: severity
                )
              end

            if result.success?
              notification = result.record
              Pito::CableBroadcaster.broadcast_panel(
                NOTIFICATIONS_FEED_CHANNEL,
                kind:    :notification_created,
                payload: {
                  id:       notification.id,
                  category: category.to_s,
                  kind:     kind.to_s,
                  severity: severity.to_s,
                  title:    notification.title
                }
              )
              created += 1
              puts "  [#{created}/#{grand_total}] #{category} id=#{notification.id} — #{message.inspect}"
            else
              failed += 1
              puts "  [FAILED] #{category} — #{result.errors.join(', ')}"
            end

            sleep(delay_s) if delay_s > 0 && (created + failed) < grand_total
          end
        end

        puts "[pito:test:notifications:seed] done — created=#{created} failed=#{failed}"
      end

      desc "destroy ALL notifications (hard reset — removes every row regardless of origin)"
      task reset: :environment do
        count = Notification.delete_all
        puts "[pito:test:notifications:reset] deleted #{count} notification(s)"
      end
    end
  end
end
