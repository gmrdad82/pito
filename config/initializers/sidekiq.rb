Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:64527/0") }

  # Beta 4 — Phase F1 Lane A. After every job runs, broadcast Sidekiq
  # queue-depth stats (busy / enqueued / retry / scheduled) to
  # `pito:status_bar` so the top status bar can update via cable
  # without polling. See `app/sidekiq/status_bar_broadcast_middleware.rb`.
  config.server_middleware do |chain|
    chain.add(StatusBarBroadcastMiddleware)
  end

  # DISABLED until further notice (user request 2026-05-18) — no scheduled
  # background work should run. To re-enable: uncomment the block below and
  # restart bin/dev. The schedule itself in config/sidekiq_cron.yml is intact.
  #
  # config.on(:startup) do
  #   schedule_file = Rails.root.join("config", "sidekiq_cron.yml")
  #   if schedule_file.exist?
  #     schedule = YAML.load_file(schedule_file)
  #     Sidekiq::Cron::Job.load_from_hash(schedule) if schedule.present?
  #   end
  # end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:64527/0") }
end
