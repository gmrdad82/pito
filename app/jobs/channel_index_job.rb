# Phase B (2026-05-19) — Meilisearch index job for Channel.
#
# Standalone job that fans the Channel after_save_commit callback out
# to the `Meilisearch::ChannelIndexer` service. Decoupled from the
# generic `SearchIndexJob` to keep the Channel pipeline fully
# independent of the Game / Bundle / Searchable-concern stack.
class ChannelIndexJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    channel = Channel.find_by(id: channel_id)
    return if channel.nil?

    Meilisearch::ChannelIndexer.new(channel).call
  end
end
