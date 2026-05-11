module Platforms
  # Phase 27 §1a — Sidekiq wrapper for `Platforms::SyncFromIgdb`.
  # Cron-triggered weekly (see `config/sidekiq_cron.yml`) and invoked
  # ad-hoc via the `platforms:sync_from_igdb` rake task.
  class SyncFromIgdbJob
    include Sidekiq::Job
    sidekiq_options queue: "default", retry: 3

    def perform
      result = Platforms::SyncFromIgdb.call
      Rails.logger.info(
        "[Platforms::SyncFromIgdbJob] created=#{result.created} " \
        "updated=#{result.updated} total=#{result.total}"
      )
      result
    end
  end
end
