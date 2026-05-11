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

# Phase 7 — Step A (7a-google-oauth-and-identity.md). OmniAuth-based
# Google OAuth flow. `omniauth-rails_csrf_protection` is required by
# OmniAuth 2.x to keep request-phase routes POST-only (CVE-2015-9284).
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"

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

# Phase 25 — 01e. TOTP 2FA (`rotp`) + QR-code rendering (`rqrcode`).
# `rotp` generates and verifies the standard `otpauth://totp/...` URIs and
# 6-digit codes (RFC 6238); `rqrcode` renders the URI as an SVG payload
# so the enrollment view can show the QR scan target without an external
# image service. Both gems are pure Ruby — no native extensions.
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 2.2"

# MCP (Model Context Protocol) server
gem "mcp"

# Phase 12 — Step B (6b-doorkeeper-oauth-server.md). OAuth 2.0 authorization
# server. Authorization Code + PKCE only; Client Credentials and ROPC are
# disabled in `config/initializers/doorkeeper.rb` per the locked decisions.
gem "doorkeeper", "~> 5.8"

# Phase 20 — friendly URLs. Renameable resources (Project, Bundle, Collection,
# MilestoneRule) get a `slug` column with `:slugged` + `:history`; identifier-
# style resources (Channel, Video, Game, Footage) reuse an existing column via
# `to_param` override + `:finders`. See
# `docs/plans/beta/20-friendly-urls/specs/01-friendly-urls-app-wide.md`.
gem "friendly_id", "~> 5.5"
