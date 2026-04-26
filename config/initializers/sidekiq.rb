Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6380/0") }

  config.on(:startup) do
    schedule_file = Rails.root.join("config", "sidekiq_cron.yml")
    if schedule_file.exist?
      schedule = YAML.load_file(schedule_file)
      Sidekiq::Cron::Job.load_from_hash(schedule) if schedule.present?
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6380/0") }
end
