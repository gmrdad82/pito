class SearchIndexJob < ApplicationJob
  queue_as :search

  def perform(class_name, id)
    record = class_name.constantize.find_by(id: id)
    return unless record

    Search.engine.index(record)
  end
end
