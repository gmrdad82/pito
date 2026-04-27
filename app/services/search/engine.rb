module Search
  class Engine
    def index(record)
      raise NotImplementedError
    end

    def remove(record)
      raise NotImplementedError
    end

    def reindex_all(model)
      raise NotImplementedError
    end

    # Returns { hits: [...], total: Integer, took_ms: Float }
    def search(model, query, page: 1, per_page: 20, filters: {})
      raise NotImplementedError
    end

    def healthy?
      raise NotImplementedError
    end

    def index_stats
      raise NotImplementedError
    end

    private

    def index_name_for(model_or_record)
      klass = model_or_record.is_a?(Class) ? model_or_record : model_or_record.class
      "#{klass.name.underscore.pluralize}_#{Rails.env}"
    end
  end
end
