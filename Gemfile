source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"
gem "importmap-rails", "~> 2.1"
gem "propshaft", "~> 1.3"
gem "tailwindcss-rails", "~> 4.6"
gem "view_component", "~> 4.12"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "thruster", "~> 0.1", require: false
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", "~> 1.24", require: false

# Rack::Attack throttles the login, TOTP-management, and password-reset
# surfaces (per-IP buckets). Backed by the Rails cache store.

# Solid* gems — Postgres-backed queue, cache, and cable
gem "solid_queue", "~> 1.4"
gem "solid_cache", "~> 1.0"
gem "solid_cable", "~> 4.0"

# YouTube APIs
gem "google-apis-youtube_v3", "~> 0.66"
gem "google-apis-youtube_analytics_v2", "~> 0.19"
# google-apis-core (1.1.0+) requires multi_json at runtime but no longer declares
# it, so the 0.65 bump drops it from the lock and the bundle fails to load
# ("multi_json is not part of the bundle"). Pin it explicitly to keep it present.
gem "multi_json", "~> 1.15"

# Phase 7 — Step A (7a-google-oauth-and-identity.md). OmniAuth-based
# Google OAuth flow. `omniauth-rails_csrf_protection` is required by
# OmniAuth 2.x to keep request-phase routes POST-only (CVE-2015-9284).
gem "omniauth-google-oauth2", "~> 1.2"
gem "omniauth-rails_csrf_protection", "~> 2.0"

# Phase 4 — Project Workspace
# image_processing: Active Storage variant pipeline (Game cover art).
# Backed by ruby-vips (libvips) — see config.active_storage.variant_processor
# in config/application.rb. Spec §5 explicitly forbids mini_magick.
gem "image_processing", "~> 2.0"
# ruby-vips eagerly opens libvips.so.42 at require time. We pin it for the
# bundle (image_processing transitively requires it), but skip the auto-
# require: image_processing/vips.rb pulls it on-demand the moment a variant
# is generated. This keeps Rails bootable on hosts without libvips installed
# (Phase A has no variant code paths exercised in specs); install
# libvips at the system level before Phase B's cover-art tests run.
gem "ruby-vips", "~> 2.2", require: false
# neighbor: Active Record bridge for pgvector cosine queries on notes.embedding.
gem "neighbor", "~> 1.2"

group :development, :test do
  # Pure-Ruby CDP driver for the capture tool (rake pito:capture) — drives the
  # ms-playwright Chrome Headless Shell already on disk; no Node toolchain.
  gem "ferrum", "~> 0.17"

  gem "pry-rails", "~> 0.3"
  gem "debug", "~> 1.11", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", "~> 0.9", require: false
  gem "brakeman", "~> 8.0", require: false
  gem "rubocop-rails-omakase", "~> 1.1", require: false

  # Testing
  gem "rspec-rails", "~> 8.0"
  # Coverage floor (mirrors pito-tui's Go gate): opt-in via COVERAGE=1 locally,
  # always-on in CI; the merged-floor enforcement lives in rake coverage:floor.
  gem "simplecov", "~> 0.22", require: false
  gem "factory_bot_rails", "~> 6.5"
  gem "faker", "~> 3.8"
  gem "shoulda-matchers", "~> 8.0"
  gem "webmock", "~> 3.26"
  # parallel_tests: per-CPU Postgres test DBs (`pito_test`, `pito_test_2`, ...)
  # plus the `parallel_rspec` runner. Run `bin/parallel_setup` once after a
  # fresh checkout, then `bundle exec parallel_rspec spec/`. CI's `rails` job
  # uses the same pair; see .github/workflows/ci.yml.
  gem "parallel_tests", "~> 5.7"
end

group :development do
  gem "ruby-lsp", "~> 0.26", require: false
  # gem "web-console" — removed Phase 1 (no web views)
end

# gem "capybara" — removed Phase 1 (no web UI to test)

# gem "draper" — removed Phase 1 (no web views)

# Phase 25 — 01e. TOTP 2FA. `rotp` generates and verifies the standard
# `otpauth://totp/...` URIs and 6-digit codes (RFC 6238); pure Ruby.
gem "rotp", "~> 6.3"

gem "countries", "~> 8.1"
