# Canonical absolute base URL for the Pito web Puma (`app.pitomd.com`).
# The host is stable across environments — both production and the dev
# Cloudflare tunnel terminate on the same name — so the OAuth metadata
# document (`/.well-known/oauth-authorization-server`) can hardcode it
# without consulting `request.host`.
#
# Why hardcode (not derive from `request.host`): the OAuth metadata
# MUST advertise `issuer = the authorization-server origin` regardless
# of which subdomain the request happened to land on. A consistent
# issuer value is required for clients that probe metadata from
# multiple subdomains.
#
# Override knob (test-only): `ENV["PITO_APP_BASE_URL"]` lets request
# specs and CI environments replace the canonical host without
# touching the constant.
module Pito
  module PublicHosts
    DEFAULT_APP_BASE = "https://app.pitomd.com"

    module_function

    def app_base
      ENV.fetch("PITO_APP_BASE_URL", DEFAULT_APP_BASE).chomp("/")
    end
  end
end
