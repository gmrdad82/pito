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

    # Optional. Engines that expose on-disk size metrics override
    # this; the default returns nil so the settings view can render
    # neutrally on engines that don't.
    def total_index_size_bytes
      nil
    end

    # Optional. Engines that expose per-index document counts + size
    # override this. Default returns an empty hash so the settings
    # view renders neutrally on engines that don't.
    def per_index_stats
      {}
    end

    private

    def index_name_for(model_or_record)
      klass = model_or_record.is_a?(Class) ? model_or_record : model_or_record.class
      "#{klass.name.underscore.pluralize}_#{Rails.env}"
    end
  end
end
