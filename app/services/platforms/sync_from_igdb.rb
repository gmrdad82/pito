module Platforms
  # Phase 27 §1a — sync the local `platforms` table against the IGDB
  # `/platforms` endpoint. Upserts by `igdb_id`. Never deletes — a
  # platform a user owns games on must outlive any IGDB churn.
  #
  # Idempotent: running back-to-back yields the same row set after the
  # first successful pass.
  #
  # The result struct carries integer counts so the calling job can log
  # something deterministic in addition to the structured Sidekiq job
  # log line.
  class SyncFromIgdb
    Result = Struct.new(:created, :updated, :total, keyword_init: true)

    class << self
      def call(client: Game::Igdb::Client.new)
        new(client: client).call
      end
    end

    def initialize(client: Game::Igdb::Client.new)
      @client = client
    end

    def call
      rows = @client.list_all_platforms
      created = 0
      updated = 0

      Array(rows).each do |row|
        next unless row.is_a?(Hash)

        attrs = Game::Igdb::GameMapper.map_platform(row)
        igdb_id = attrs[:igdb_id]
        next unless igdb_id.is_a?(Integer) && igdb_id.positive?

        platform = Platform.unscoped.find_or_initialize_by(igdb_id: igdb_id)
        if platform.new_record?
          # New row — fill name, save (FriendlyId derives the slug from
          # name during `before_validation`), then stamp the IGDB slug
          # via `update_column` so the FriendlyId generator doesn't
          # overwrite it. Using update_column also skips a redundant
          # save callback round-trip.
          platform.name = attrs[:name]
          platform.save!
          if attrs[:slug].present? && platform.slug != attrs[:slug]
            platform.update_column(:slug, attrs[:slug])
          end
          created += 1
        else
          # Leave `slug` untouched on existing rows so user-facing
          # routes stay stable. FriendlyId history captures renames
          # downstream if the user edits the platform by hand.
          if attrs[:name].present? && platform.name != attrs[:name]
            platform.name = attrs[:name]
            platform.save!
            updated += 1
          end
        end
      end

      Result.new(created: created, updated: updated, total: Platform.unscoped.count)
    rescue Game::Igdb::Client::Error => e
      Rails.logger.error("[Platforms::SyncFromIgdb] IGDB error: #{e.class} #{e.message}")
      raise
    end
  end
end
