source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "propshaft"
gem "mysql2", "~> 0.5"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# Redis (for Rails cache store)
gem "redis", ">= 4.0.1"

# Background jobs
gem "sidekiq"
gem "sidekiq-cron"

# YouTube APIs
gem "google-apis-youtube_v3"
gem "google-apis-youtube_analytics_v2"

# Charts
gem "chartkick"
gem "groupdate"

# Environment
gem "dotenv-rails"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "pry-rails"

  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "webmock"
end

group :development do
  gem "web-console"
end

gem "view_component", "~> 4.8"

gem "capybara", "~> 3.40", group: :test

gem "draper", "~> 4.0"
