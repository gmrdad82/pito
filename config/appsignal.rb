# frozen_string_literal: true

# AppSignal (APM + error tracking + log forwarding) configuration.
#
# Activation is deliberately double-gated:
#   - production only — dev/test never start the agent;
#   - APPSIGNAL_PUSH_API_KEY present — the key reaches the container as an
#     env var from the operator's install-dir .env (docker-compose
#     `environment:` passthrough), never from the repo, the public image,
#     or Rails encrypted credentials. Without it — every other self-hoster —
#     AppSignal stays completely inert and the app boots exactly as before.
#
# The web container's single Puma process hosts HTTP + SolidQueue
# (SOLID_QUEUE_IN_PUMA) + recurring jobs, so this one config instruments all
# of them; the pito-mcp container picks it up through the same env var.
Appsignal.configure do |config|
  config.active = config.env == "production" && ENV["APPSIGNAL_PUSH_API_KEY"].present?
  config.name = "pito"

  # Deploy markers: PITO_VERSION is baked into the image at build time by the
  # release workflow, so every `pito update` shows up as a deploy.
  config.revision = ENV["PITO_VERSION"].presence

  # Noise controls: the tui/cable-health version poll and the /up health
  # endpoint fire constantly and would bury real traffic in the dashboards.
  config.ignore_actions = [
    "VersionsController#show",
    "Rails::HealthController#show"
  ]
end
