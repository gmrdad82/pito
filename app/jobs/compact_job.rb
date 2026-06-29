# frozen_string_literal: true

# No-op placeholder for conversation compaction.
# Real implementation comes later. Logs the request and returns.
class CompactJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    Rails.logger.info("[CompactJob] compact requested for conversation #{conversation_id} (no-op)")
  end
end
