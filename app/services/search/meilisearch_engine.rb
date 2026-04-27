module Search
  class MeilisearchEngine < Engine
    def initialize(url: nil, api_key: nil)
      @client = Meilisearch::Client.new(
        url || ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7700"),
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

    def index_stats
      stats = @client.stats
      indexes = stats["indexes"] || {}
      indexes.transform_values { |v| v["numberOfDocuments"] }
    rescue StandardError
      {}
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
