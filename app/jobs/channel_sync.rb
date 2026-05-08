class ChannelSync
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  # Phase 7 Path A2 (literal full retract) — no-op stub. The placeholder
  # `syncing` boolean is gone; Phase 8+ will replace this stub with the
  # real YouTube sync wiring (which will own in-flight state via the
  # BulkOperation surface, not via a per-row column flag). Until then
  # the job loads the row, stamps `last_synced_at`, and exits.
  def perform(channel_id)
    channel = Channel.find_by(id: channel_id)
    return unless channel

    channel.update_columns(last_synced_at: Time.current)
  end
end
