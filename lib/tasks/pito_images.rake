# frozen_string_literal: true

# Maintenance for ActiveStorage images (game covers + video thumbnails) whose
# backing file went missing from the storage service (e.g. a wiped `storage/`),
# leaving a broken <img>. See Pito::Maintenance::ImageSweep.
#
#   rake pito:images:sweep   # report games/videos with a missing blob file
#   rake pito:images:fix     # re-attach them from source (IGDB / YouTube)
namespace :pito do
  namespace :images do
    desc "Report game covers / video thumbnails whose blob file is missing on disk"
    task sweep: :environment do
      m = Pito::Maintenance::ImageSweep.missing
      puts "Games with a missing cover file:  #{m[:games].size}"
      m[:games].each  { |g| puts "  game  ##{g.id} — #{g.title}" }
      puts "Videos with a missing thumb file: #{m[:videos].size}"
      m[:videos].each { |v| puts "  video ##{v.id} — #{v.title}" }
      puts(m[:games].empty? && m[:videos].empty? ? "All image files present. Nothing to fix." : "Run `rake pito:images:fix` to re-attach.")
    end

    desc "Re-attach game covers / video thumbnails whose blob file is missing"
    task fix: :environment do
      result = Pito::Maintenance::ImageSweep.repair
      puts "Covers re-attached:      #{result[:games_fixed]}"
      puts "Thumbnails re-attached:  #{result[:videos_fixed]}"
      puts "Videos skipped (no/reauth connection): #{result[:videos_skipped]}" if result[:videos_skipped].positive?
    end
  end
end
