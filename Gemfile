source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"
gem "importmap-rails", "~> 2.1"
gem "propshaft", "~> 1.3"
gem "tailwindcss-rails", "~> 4.4"
gem "view_component", "~> 4.11"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "jbuilder", "~> 2.14"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", "~> 1.24", require: false

# Rack::Attack throttles the login, TOTP-management, and password-reset
# surfaces (per-IP buckets). Backed by the Rails cache store.

# Solid* gems — Postgres-backed queue, cache, and cable
gem "solid_queue", "~> 1.4"
gem "solid_cache", "~> 1.0"
gem "solid_cable", "~> 4.0"

# YouTube APIs
gem "google-apis-youtube_v3", "~> 0.64"

# Phase 7 — Step A (7a-google-oauth-and-identity.md). OmniAuth-based
# Google OAuth flow. `omniauth-rails_csrf_protection` is required by
# OmniAuth 2.x to keep request-phase routes POST-only (CVE-2015-9284).
gem "omniauth-google-oauth2", "~> 1.2"
gem "omniauth-rails_csrf_protection", "~> 2.0"

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
# neighbor: Active Record bridge for pgvector cosine queries on notes.embedding.
gem "neighbor", "~> 1.1"

group :development, :test do
  gem "pry-rails", "~> 0.3"
  gem "debug", "~> 1.11", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", "~> 0.9", require: false
  gem "brakeman", "~> 8.0", require: false
  gem "rubocop-rails-omakase", "~> 1.1", require: false

  # Testing
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.5"
  gem "faker", "~> 3.8"
  gem "shoulda-matchers", "~> 7.0"
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

# Phase 25 — 01e. TOTP 2FA (`rotp`) + QR-code rendering (`rqrcode`).
# `rotp` generates and verifies the standard `otpauth://totp/...` URIs and
# 6-digit codes (RFC 6238); `rqrcode` renders the URI as an SVG payload
# so the enrollment view can show the QR scan target without an external
# image service. Both gems are pure Ruby — no native extensions.
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 3.2"
