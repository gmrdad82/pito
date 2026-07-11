# frozen_string_literal: true

# The version heartbeat: every 5 minutes, push the running build's
# identity onto pito:global. This is how open tabs learn the server was
# updated UNDER them — the one-shot reconnect check (cable-health) can miss
# the update's reconnect churn, but a recurring push reaches every client
# that is connected at ANY tick after the dust settles; pito--version-watch
# compares it against the page's own build and raises the refresh nudge.
class VersionHeartbeatJob < ApplicationJob
  queue_as :default

  def perform
    Pito::Stream::Broadcaster.broadcast_global_version
  end
end
