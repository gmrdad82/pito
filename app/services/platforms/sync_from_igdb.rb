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
      def call(client: Igdb::Client.new)
        new(client: client).call
      end
    end

    def initialize(client: Igdb::Client.new)
      @client = client
    end

    def call
      rows = @client.list_all_platforms
      created = 0
      updated = 0

      Array(rows).each do |row|
        next unless row.is_a?(Hash)

        attrs = Igdb::GameMapper.map_platform(row)
        igdb_id = attrs[:igdb_id]
        next unless igdb_id.is_a?(Integer) && igdb_id.positive?

        platform = Platform.unscoped.find_or_initialize_by(igdb_id: igdb_id)
        if platform.new_record?
          # New row — fill every IGDB-derived attribute including slug.
          # FriendlyId backfills slug from name if IGDB's slug is blank
          # via `slug_candidates`; the explicit IGDB slug takes
          # precedence when present.
          platform.name = attrs[:name]
          platform.abbreviation = attrs[:abbreviation]
          platform.slug = attrs[:slug].presence
          platform.save!
          created += 1
        else
          changed = false
          if attrs[:name].present? && platform.name != attrs[:name]
            platform.name = attrs[:name]
            changed = true
          end
          if attrs.key?(:abbreviation) && platform.abbreviation != attrs[:abbreviation]
            platform.abbreviation = attrs[:abbreviation]
            changed = true
          end
          # Leave `slug` untouched on existing rows so user-facing
          # routes stay stable. FriendlyId history captures renames
          # downstream if the user edits the platform by hand.
          if changed
            platform.save!
            updated += 1
          end
        end
      end

      Result.new(created: created, updated: updated, total: Platform.unscoped.count)
    rescue Igdb::Client::Error => e
      Rails.logger.error("[Platforms::SyncFromIgdb] IGDB error: #{e.class} #{e.message}")
      raise
    end
  end
end
