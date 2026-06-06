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

    # ViewComponent preview paths (Plan 0 P10.4). Plan 1 doesn't use
    # Lookbook or previews, but the path is wired now so future previews
    # under spec/components/previews/ work without further config.
    config.view_component.preview_paths = [ Rails.root.join("spec/components/previews").to_s ]

    # Postgres stores timestamps as timestamptz; pin Rails to UTC so Groupdate
    # aggregates render predictably.
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Use SolidQueue for background jobs (runs in-process in Puma in dev)
    config.active_job.queue_adapter = :solid_queue

    # Active Storage variant processor — Phase 4 §5. Use ruby-vips (libvips)
    # explicitly. ImageMagick v7.1.2 deprecated the `convert` alias that
    # mini_magick relies on, so mini_magick emits warnings on every variant.
    # ruby-vips is faster, lower-memory, and sidesteps the warning entirely.
    config.active_storage.variant_processor = :vips

    # Voyage AI embedding call gating moved to AppSetting (DB-backed) so the
    # Settings UI flips it at runtime without a Rails restart. See
    # `AppSetting.voyage_configured?` — credentials presence is the only
    # gate now that the per-target Notes flag is gone (Notes dropped D17).

    # Route 404/422/500 through the Rails app so the 404 page renders the
    # full start screen with the autocomplete-enabled chatbox, instead of
    # the static public/404.html fallback.
    config.exceptions_app = routes

    # Theme definition files (app/services/pito/themes/definitions/*.rb)
    # intentionally define NO constant — each just calls Registry.register.
    # Zeitwerk cannot autoload/eager-load them (it would raise NameError).
    # The Registry requires them explicitly via Dir.glob, so telling Zeitwerk
    # to ignore the directory is the correct fix (Rails Guide §13.1).
    Rails.autoloaders.main.ignore(
      Rails.root.join("app/services/pito/themes/definitions")
    )
  end
end
