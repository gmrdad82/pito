# Canonical absolute base URL for the Pito web Puma. Defaults to the
# local dev host; deployments override it via `ENV["PITO_APP_BASE_URL"]`.
# The OAuth metadata document
# (`/.well-known/oauth-authorization-server`) uses this base without
# consulting `request.host`.
#
# Why a fixed base (not derived from `request.host`): the OAuth metadata
# MUST advertise `issuer = the authorization-server origin` regardless
# of which host the request happened to land on. A consistent issuer
# value is required for clients that probe metadata from multiple hosts.
#
# Override knob: `ENV["PITO_APP_BASE_URL"]` lets deployments, request
# specs, and CI environments replace the base without touching the
# constant.
require "uri"

module Pito
  module PublicHosts
    DEFAULT_APP_BASE = "http://localhost:3027"

    module_function

    def app_base
      ENV.fetch("PITO_APP_BASE_URL", DEFAULT_APP_BASE).chomp("/")
    end

    # True when the operator explicitly set a public base URL (vs the dev
    # default). Production host/asset wiring only engages when this is true.
    def configured?
      ENV["PITO_APP_BASE_URL"].present?
    end

    def app_uri
      URI.parse(app_base)
    end

    # Host component of the base URL (e.g. "app.pitomd.com"), or nil if the
    # base URL is unparseable / hostless.
    def host
      app_uri.host
    end

    # Scheme component ("http" / "https").
    def scheme
      app_uri.scheme
    end
  end
end
