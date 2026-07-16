require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# PB-1: referenced by class name below (config.middleware.insert_before) while
# the Pito::Application class body is still evaluating — before Zeitwerk's
# autoloader for app/middleware is engaged (that happens later, during
# Rails.application.initialize!). Require it explicitly so the constant
# resolves at boot; Zeitwerk still owns eager-loading/reloading it afterward.
require_relative "../app/middleware/pito/bad_request_guard"

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

    # ViewComponent preview paths. The path is wired so future previews
    # under spec/components/previews/ work without further config.
    config.view_component.preview_paths = [ Rails.root.join("spec/components/previews").to_s ]

    # Postgres stores timestamps as timestamptz; pin Rails to UTC so Groupdate
    # aggregates render predictably.
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Use SolidQueue for background jobs (runs in-process in Puma in dev)
    config.active_job.queue_adapter = :solid_queue

    # Active Storage variant processor — use ruby-vips (libvips)
    # explicitly. ImageMagick v7.1.2 deprecated the `convert` alias that
    # mini_magick relies on, so mini_magick emits warnings on every variant.
    # ruby-vips is faster, lower-memory, and sidesteps the warning entirely.
    config.active_storage.variant_processor = :vips

    # Route 404/422/500 through the Rails app so the 404 page renders the
    # full start screen with the suggestions-enabled chatbox, instead of
    # the static public/404.html fallback.
    config.exceptions_app = routes

    # Theme definition files (lib/pito/themes/definitions/*.rb)
    # intentionally define NO constant — each just calls Registry.register.
    # Zeitwerk cannot autoload/eager-load them (it would raise NameError).
    # The Registry requires them explicitly via Dir.glob, so telling Zeitwerk
    # to ignore the directory is the correct fix (Rails Guide §13.1).
    Rails.autoloaders.main.ignore(
      Rails.root.join("lib/pito/themes/definitions")
    )

    # PB-1: return 400 (not 500) for malformed bot-probe requests (bogus
    # multipart boundaries, unparseable params) that Rack::MethodOverride
    # raises on while reading params. Must sit ABOVE MethodOverride so it
    # wraps the call where the parse raises — see Pito::BadRequestGuard.
    config.middleware.insert_before Rack::MethodOverride, Pito::BadRequestGuard
  end
end
