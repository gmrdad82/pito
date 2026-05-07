source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "propshaft"
gem "pg", "~> 1.5"
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

# Phase 3 — Step B. Rack::Attack throttles failed bearer-token lookups
# (10 failures / 5 min / IP). Backed by the Rails cache store (Redis in
# dev/prod, MemoryStore in test).
gem "rack-attack"

# Background jobs
gem "sidekiq"
gem "sidekiq-cron"

# YouTube APIs
gem "google-apis-youtube_v3"
gem "google-apis-youtube_analytics_v2"

# Charts
gem "chartkick"
gem "groupdate"

# Search
gem "meilisearch"

# Environment
gem "dotenv-rails"

# Use Active Model has_secure_password
gem "bcrypt", "~> 3.1.7"

# Phase 4 — Project Workspace
# image_processing: Active Storage variant pipeline (Game cover art).
# Backed by ruby-vips (libvips) — see config.active_storage.variant_processor
# in config/application.rb. Spec §5 explicitly forbids mini_magick.
gem "image_processing", "~> 1.14"
# ruby-vips eagerly opens libvips.so.42 at require time. We pin it for the
# bundle (image_processing transitively requires it), but skip the auto-
# require: image_processing/vips.rb pulls it on-demand the moment a variant
# is generated. This keeps Rails bootable on hosts without libvips installed
# (Phase A has no variant code paths exercised in specs); install
# libvips at the system level before Phase B's cover-art tests run.
gem "ruby-vips", "~> 2.2", require: false
# aasm: state machines for Timeline (editing/exported/uploaded) and Video.
gem "aasm", "~> 5.5"
# commonmarker: GFM markdown rendering for note bodies (Phase B helper).
gem "commonmarker", "~> 2.4"
# neighbor: Active Record bridge for pgvector cosine queries on notes.embedding.
gem "neighbor", "~> 0.6"

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
  # parallel_tests: per-CPU Postgres test DBs (`pito_test`, `pito_test_2`, ...)
  # plus the `parallel_rspec` runner. Run `bin/parallel_setup` once after a
  # fresh checkout, then `bundle exec parallel_rspec spec/`. CI's `rails` job
  # uses the same pair; see .github/workflows/ci.yml.
  gem "parallel_tests"
end

group :development do
  gem "web-console"
end

gem "view_component", "~> 4.8"

gem "capybara", "~> 3.40", group: :test

gem "draper", "~> 4.0"

# MCP (Model Context Protocol) server
gem "mcp"
