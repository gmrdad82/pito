module Pito
  module Search
    class MeilisearchEngine < Engine
      def initialize(url: nil, api_key: nil)
        @client = Meilisearch::Client.new(
          url || ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7727"),
          api_key
        )
      end

      def index(record)
        return unless record.class.respond_to?(:searchable_fields)

        idx = @client.index(index_name_for(record))
        idx.add_documents([ searchable_document(record) ], "id")
      end

      def remove(record)
        idx = @client.index(index_name_for(record))
        idx.delete_document(record.id)
      rescue Meilisearch::ApiError => e
        raise unless e.message.include?("not found")
      end

      def reindex_all(model)
        idx = @client.index(index_name_for(model))

        configure_index(idx, model)

        idx.delete_all_documents
        model.find_in_batches(batch_size: 500) do |batch|
          docs = batch.map { |record| searchable_document(record) }
          idx.add_documents(docs, "id")
        end
      end

      def search(model, query, page: 1, per_page: 20, filters: {})
        idx = @client.index(index_name_for(model))

        params = {
          limit: per_page,
          offset: (page - 1) * per_page,
          attributes_to_highlight: [ "*" ],
          highlight_pre_tag: "<mark>",
          highlight_post_tag: "</mark>"
        }

        if filters.any?
          filter_parts = filters.map { |k, v| "#{k} = #{filter_value(v)}" }
          params[:filter] = filter_parts.join(" AND ")
        end

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = idx.search(query, **params)
        took_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)

        {
          hits: result["hits"].map { |h| deserialize_hit(h, model) },
          total: result["estimatedTotalHits"] || result["totalHits"] || 0,
          took_ms: took_ms
        }
      rescue Meilisearch::ApiError => e
        raise unless e.message.include?("not found")
        { hits: [], total: 0, took_ms: 0 }
      end

      def healthy?
        @client.healthy?
      rescue StandardError
        false
      end

      # Returns the Meilisearch server version string (e.g. "1.10.3"),
      # or nil when the engine is unreachable or the version endpoint
      # is unavailable. Used by `Pito::Stack::MeilisearchSubPanelComponent`
      # to render the hint line (`Meilisearch v<version> connected`).
      def version
        info = @client.version
        info["pkgVersion"] || info["commitDate"]
      rescue StandardError
        nil
      end

      def index_stats
        stats = @client.stats
        indexes = stats["indexes"] || {}
        indexes.transform_values { |v| v["numberOfDocuments"] }
      rescue StandardError
        {}
      end

      # 2026-05-11 — total on-disk size for every index Meilisearch
      # reports under `/stats`. The endpoint returns a top-level
      # `databaseSize` field (sum across indexes) plus per-index
      # `databaseSize` fields. We prefer the top-level value when
      # present; otherwise we sum the per-index entries. Returns the
      # value in bytes, or nil when the engine doesn't expose the
      # metric / the request fails — the settings view hides the row
      # when nil.
      def total_index_size_bytes
        stats = @client.stats
        top = stats["databaseSize"]
        return top.to_i if top.is_a?(Numeric) || top.to_s.match?(/\A\d+\z/)
        indexes = stats["indexes"] || {}
        summed = indexes.values.sum { |v| v["databaseSize"].to_i }
        summed.positive? ? summed : nil
      rescue StandardError
        nil
      end

      # 2026-05-11 (later) — per-index breakdown for the `search` panel.
      # Returns a hash keyed by raw index name (e.g. `"channels_development"`)
      # with `:documents` + `:size_bytes` values. `databaseSize` is the
      # most-comprehensive on-disk figure Meilisearch reports per index
      # (newer versions); we fall back to `rawDocumentDbSize` when only
      # that surfaces. The view sums nothing — it iterates and renders
      # each row. Returns `{}` on engine failure so the view simply hides
      # the breakdown.
      def per_index_stats
        stats = @client.stats
        indexes = stats["indexes"] || {}
        indexes.each_with_object({}) do |(name, payload), acc|
          size = payload["databaseSize"] || payload["rawDocumentDbSize"]
          acc[name] = {
            documents: payload["numberOfDocuments"].to_i,
            size_bytes: size.nil? ? nil : size.to_i
          }
        end
      rescue StandardError
        {}
      end

      # 2026-05-18 — count documents within an index that match a single
      # equality filter (the unified `games_<env>` index holds both Game
      # and Bundle documents distinguished by the `kind` field, so this
      # is how the stack panel splits one physical index into two display
      # rows). Returns the integer hit estimate, or nil on failure so the
      # view can render "—" without raising.
      def documents_count_for(index_name, field:, value:)
        idx = @client.index(index_name)
        result = idx.search(
          "",
          filter: "#{field} = #{filter_value(value)}",
          limit: 0
        )
        (result["estimatedTotalHits"] || result["totalHits"] || 0).to_i
      rescue StandardError
        nil
      end

      private

      def searchable_document(record)
        fields = record.class.searchable_fields
        doc = { "id" => record.id }
        fields.each do |field|
          value = record.public_send(field)
          doc[field.to_s] = value.is_a?(Array) ? value : value.to_s
        end

        if record.class.respond_to?(:filterable_fields)
          record.class.filterable_fields.each do |field|
            next if doc.key?(field.to_s)
            doc[field.to_s] = record.public_send(field)
          end
        end

        doc
      end

      def configure_index(idx, model)
        searchable = model.searchable_fields.map(&:to_s)
        idx.update_searchable_attributes(searchable)

        if model.respond_to?(:filterable_fields)
          idx.update_filterable_attributes(model.filterable_fields.map(&:to_s))
        end
      end

      def filter_value(val)
        case val
        when true, false then val.to_s
        when Integer then val.to_s
        else "\"#{val}\""
        end
      end

      def deserialize_hit(hit, model)
        {
          id: hit["id"],
          record: model.find_by(id: hit["id"]),
          highlights: hit["_formatted"] || {},
          score: hit["_rankingScore"]
        }
      end
    end
  end
end
