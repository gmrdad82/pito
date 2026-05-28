source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "turbo-rails"
gem "importmap-rails", "~> 2.1"
gem "propshaft"
gem "tailwindcss-rails"
gem "view_component"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

# Rack::Attack throttles failed bearer-token lookups
# (10 failures / 5 min / IP). Backed by the Rails cache store.
gem "rack-attack"

# Solid* gems — Postgres-backed queue, cache, and cable
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# YouTube APIs
gem "google-apis-youtube_v3"

# Phase 7 — Step A (7a-google-oauth-and-identity.md). OmniAuth-based
# Google OAuth flow. `omniauth-rails_csrf_protection` is required by
# OmniAuth 2.x to keep request-phase routes POST-only (CVE-2015-9284).
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"

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
gem "neighbor", "~> 0.6"

group :development, :test do
  gem "pry-rails"
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false

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
  gem "ruby-lsp", require: false
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
gem "rqrcode", "~> 2.2"
