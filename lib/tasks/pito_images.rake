# frozen_string_literal: true

# Maintenance for ActiveStorage images (game covers + video thumbnails +
# channel avatars) whose backing file went missing from the storage service
# (e.g. a wiped `storage/` or a migration to a new storage root), leaving a
# broken <img>. See Pito::Maintenance::ImageSweep.
#
#   rake pito:images:sweep   # report games/videos/channels with a missing blob file
#   rake pito:images:fix     # re-attach them from source (IGDB / YouTube)
namespace :pito do
  namespace :images do
    desc "Report game covers / video thumbnails / channel avatars whose blob file is missing on disk"
    task sweep: :environment do
      m = Pito::Maintenance::ImageSweep.missing
      puts "Games with a missing cover file:    #{m[:games].size}"
      m[:games].each    { |g| puts "  game    ##{g.id} — #{g.title}" }
      puts "Videos with a missing thumb file:   #{m[:videos].size}"
      m[:videos].each   { |v| puts "  video   ##{v.id} — #{v.title}" }
      puts "Channels with a missing avatar file: #{m[:channels].size}"
      m[:channels].each { |c| puts "  channel ##{c.id} — #{c.title}" }
      all_empty = m[:games].empty? && m[:videos].empty? && m[:channels].empty?
      puts(all_empty ? "All image files present. Nothing to fix." : "Run `rake pito:images:fix` to re-attach.")
    end

    desc "Re-attach game covers / video thumbnails / channel avatars whose blob file is missing"
    task fix: :environment do
      result = Pito::Maintenance::ImageSweep.repair
      puts "Covers re-attached:      #{result[:games_fixed]}"
      puts "Thumbnails re-attached:  #{result[:videos_fixed]}"
      puts "Avatars re-attached:     #{result[:channels_fixed]}"
      puts "Videos skipped (no/reauth connection):   #{result[:videos_skipped]}"   if result[:videos_skipped].positive?
      puts "Channels skipped (no/reauth connection): #{result[:channels_skipped]}" if result[:channels_skipped].positive?
    end

    # Re-derive every DISPLAY VARIANT from the stored MASTER blob. Run this after
    # re-syncing channels / videos / games (which fetch + attach the raw masters),
    # or any time the variant dimensions change. Idempotent + safe to re-run; runs
    # in the pito Docker CLI / production. (13.26)
    #   rake pito:images:regenerate
    desc "Regenerate all display variants (banner/avatar/thumbnail/cover) from their master blobs"
    task regenerate: :environment do
      count = 0

      Channel.find_each do |c|
        if c.banner.attached?
          c.banner.variant(:display).processed
          count += 1
        end
        if c.avatar.attached?
          c.avatar.variant(:lg).processed
          c.avatar.variant(:sm).processed
          count += 2
        end
      end

      Video.find_each do |v|
        next unless v.thumbnail.attached?

        v.thumbnail.variant(:display).processed
        count += 1
      end

      Game.find_each do |g|
        next unless g.cover_art.attached?

        g.cover_art.variant(:detail).processed
        g.cover_art.variant(:strip).processed
        count += 2
      end

      puts "Regenerated #{count} image variants from masters."
    end
  end
end
