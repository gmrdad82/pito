class SearchRemoveJob < ApplicationJob
  queue_as :search

  def perform(class_name, id, index_name: nil)
    engine = Search.engine
    # Build a lightweight struct to pass to remove
    idx_name = index_name || "#{class_name.underscore.pluralize}_#{Rails.env}"
    client = engine.instance_variable_get(:@client)
    idx = client.index(idx_name)
    idx.delete_document(id)
  rescue Meilisearch::ApiError => e
    raise unless e.message.include?("not found")
  end
end
