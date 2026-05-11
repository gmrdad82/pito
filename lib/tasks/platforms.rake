# Phase 27 §1a — manual IGDB platform sync trigger.
#
# Runs the same code path as the weekly Sidekiq cron entry
# (`platforms_sync_from_igdb`), but inline so the operator gets
# immediate feedback. Idempotent — re-running is safe and yields zero
# created/updated counts once steady state is reached.
#
# Usage:
#   bin/rails platforms:sync_from_igdb
namespace :platforms do
  desc "Sync platforms from IGDB (`Platforms::SyncFromIgdbJob` inline)"
  task sync_from_igdb: :environment do
    result = Platforms::SyncFromIgdbJob.new.perform
    if result.respond_to?(:created)
      puts "platforms synced: created=#{result.created} " \
           "updated=#{result.updated} total=#{result.total}."
    else
      puts "platforms synced."
    end
  end
end
