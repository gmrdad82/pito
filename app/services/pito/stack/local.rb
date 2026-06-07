# frozen_string_literal: true

module Pito
  module Stack
    # Local Postgres footprint: total database size + per-entity record counts.
    # (Future: an :analytics record group once that module lands.)
    module Local
      module_function

      def db_size_bytes
        ActiveRecord::Base.connection
          .select_value("SELECT pg_database_size(current_database())").to_i
      end

      def db_size_mb
        (db_size_bytes / 1_048_576.0).round(1)
      end

      def records
        { videos: ::Video.count, games: ::Game.count }
      end

      def to_h
        { db_size_mb: db_size_mb, records: records }
      end
    end
  end
end
