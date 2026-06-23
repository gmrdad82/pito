require "active_support/core_ext/integer/time"
require "ipaddr"
require "uri"

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

  # Asset host is derived from PITO_APP_BASE_URL below (when set) so assets are
  # served from the configured public host; left relative (default) when unset.

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # HTTPS enforcement.
  #
  # Required because secure-cookie auth depends on HTTPS: the session
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

  # Trusted proxies for `request.remote_ip`.
  #
  # By default Rack walks `X-Forwarded-For` from the right and stops at the
  # first IP that is NOT in `trusted_proxies`. With an empty list any client
  # can spoof `request.remote_ip` by setting `X-Forwarded-For` themselves,
  # which defeats the Rack::Attack login throttle
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

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Public host wiring — driven by PITO_APP_BASE_URL. Read ENV inline (NOT via
  # Pito::PublicHosts): env files must not autoload app/ constants during
  # initialization — doing so raises. The parsing mirrors Pito::PublicHosts
  # (configured? / host / scheme), which is unit-tested as the contract.
  #
  # When SET (e.g. https://app.pitomd.com behind a cloudflared tunnel): lock Host
  # Authorization to that host + loopback, serve assets from it, and use it for
  # URL helpers generated outside a request (jobs, console). When UNSET: hosts
  # stay permissive and assets stay relative — the default for plain local
  # access on http://localhost:3028. SSL is always forced (assume_ssl +
  # force_ssl), so any non-localhost host must sit behind a TLS-terminating proxy
  # (see the README's Cloudflare Tunnel section).
  if ENV["PITO_APP_BASE_URL"].present?
    app_base = ENV["PITO_APP_BASE_URL"].chomp("/")
    app_uri  = URI.parse(app_base)

    if app_uri.host
      config.hosts << app_uri.host << "localhost" << "127.0.0.1"
      config.asset_host = app_base
      Rails.application.routes.default_url_options = {
        host: app_uri.host, protocol: app_uri.scheme
      }
    end
  end
end
