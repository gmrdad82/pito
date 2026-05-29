module Pito
  module Search
    class Engine
      def index(_record)
      end

      def remove(_record)
      end

      def reindex_all(_model)
      end

      def search(_model, _query, page: 1, per_page: 20, filters: {})
        { hits: [], total: 0, took_ms: 0.0 }
      end

      def healthy?
        false
      end

      def index_stats
        {}
      end

      def total_index_size_bytes
        nil
      end

      def per_index_stats
        {}
      end

      def documents_count_for(_index_name, field:, value:)
        nil
      end
    end
  end
end
