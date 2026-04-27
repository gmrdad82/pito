module Search
  def self.engine
    @engine ||= build_engine
  end

  def self.reset_engine!
    @engine = nil
  end

  def self.build_engine
    engine_name = AppSetting.get("search_engine") || "meilisearch"
    case engine_name
    when "meilisearch"
      MeilisearchEngine.new
    else
      raise "Unknown search engine: #{engine_name}"
    end
  end
  private_class_method :build_engine
end
