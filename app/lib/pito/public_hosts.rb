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
module Pito
  module PublicHosts
    DEFAULT_APP_BASE = "http://localhost:3027"

    module_function

    def app_base
      ENV.fetch("PITO_APP_BASE_URL", DEFAULT_APP_BASE).chomp("/")
    end
  end
end
