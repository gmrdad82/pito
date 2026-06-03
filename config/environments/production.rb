require "active_support/core_ext/integer/time"
require "ipaddr"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Phase 25 security F1 — HTTPS enforcement.
  #
  # Required because Phase 25 secure-cookie auth depends on HTTPS: the session
  # cookie is marked `Secure`, and HSTS pins the browser to https:// for future
  # visits. Without these two flags an attacker on the network path could
  # downgrade a request to http:// and intercept the session cookie.
  #
  # `assume_ssl` makes Rails honor `X-Forwarded-Proto: https` from the upstream
  # proxy (Cloudflare in production) so `request.ssl?` returns true even though
  # the proxy-to-Puma hop is plaintext over the loopback interface.
  #
  # `force_ssl` redirects any HTTP request to HTTPS, enables Strict-Transport-
  # Security, and marks session + auth cookies `Secure`.
  config.assume_ssl = true
  config.force_ssl  = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Phase 25 security F2 — trusted proxies for `request.remote_ip`.
  #
  # By default Rack walks `X-Forwarded-For` from the right and stops at the
  # first IP that is NOT in `trusted_proxies`. With an empty list any client
  # can spoof `request.remote_ip` by setting `X-Forwarded-For` themselves,
  # which defeats the Rack::Attack login throttle (Phase 25 — 01g, LD-11)
  # and any IP-based audit logging.
  #
  # In production every external request lands on Cloudflare first, so the
  # only legitimate proxies are Cloudflare's published edge ranges plus the
  # loopback addresses for the proxy-to-Puma hop.
  #
  # Source lists (manually encoded 2026-05-11; refresh ~yearly):
  #   IPv4: https://www.cloudflare.com/ips-v4
  #   IPv6: https://www.cloudflare.com/ips-v6
  config.action_dispatch.trusted_proxies = [
    "127.0.0.1",
    "::1",
    *%w[
      173.245.48.0/20
      103.21.244.0/22
      103.22.200.0/22
      103.31.4.0/22
      141.101.64.0/18
      108.162.192.0/18
      190.93.240.0/20
      188.114.96.0/20
      197.234.240.0/22
      198.41.128.0/17
      162.158.0.0/15
      104.16.0.0/13
      104.24.0.0/14
      172.64.0.0/13
      131.0.72.0/22
      2400:cb00::/32
      2606:4700::/32
      2803:f800::/32
      2405:b500::/32
      2405:8100::/32
      2a06:98c0::/29
      2c0f:f248::/32
    ].map { |cidr| IPAddr.new(cidr) }
  ]

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
