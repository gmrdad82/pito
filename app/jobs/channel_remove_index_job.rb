# Phase B (2026-05-19) — Meilisearch removal job for Channel.
#
# Standalone job that fans the Channel after_destroy_commit callback
# out to a direct Meilisearch delete_document call. Decoupled from
# the generic `SearchRemoveJob` to keep the Channel pipeline fully
# independent of the Game / Bundle / Searchable-concern stack.
#
# Network / "document not found" failures are swallowed — the Channel
# row is already gone from Postgres; an orphan doc in Meilisearch is
# the strictly less-bad failure mode, and the next reindex sweep
# will reconcile it.
class ChannelRemoveIndexJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    url = ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7727")
    index_name = "channels_#{Rails.env}"
    uri = URI.parse("#{url}/indexes/#{index_name}/documents/#{channel_id}")

    request = Net::HTTP::Delete.new(uri)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end
  rescue StandardError => e
    Rails.logger.warn("[ChannelRemoveIndexJob] delete failed for channel #{channel_id}: #{e.class}: #{e.message}")
  end
end
