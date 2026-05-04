require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Pito
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Postgres timezone defaults — Phase 2.
    # Postgres stores timestamps as timestamptz; pin Rails to UTC so Groupdate
    # aggregates render predictably across both Pumas and Sidekiq workers.
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Exclude app/mcp from Zeitwerk autoloading — files are required explicitly
    # because the Mcp namespace conflicts with the mcp gem's MCP constant.
    Rails.autoloaders.main.ignore(Rails.root.join("app/mcp"))

    # Use Sidekiq for background jobs
    config.active_job.queue_adapter = :sidekiq

    # Active Storage variant processor — Phase 4 §5. Use ruby-vips (libvips)
    # explicitly. ImageMagick v7.1.2 deprecated the `convert` alias that
    # mini_magick relies on, so mini_magick emits warnings on every variant.
    # ruby-vips is faster, lower-memory, and sidesteps the warning entirely.
    config.active_storage.variant_processor = :vips

    # Voyage AI embedding call gating moved to AppSetting (DB-backed) so the
    # Settings UI flips it at runtime without a Rails restart. See
    # `AppSetting.voyage_configured?` (key) and
    # `AppSetting.voyage_indexing_project_notes?` (per-target flag) — the
    # 2026-05-04 Phase B revamp split the original single Boolean into the
    # encrypted key column + per-target flag pair.
  end
end
