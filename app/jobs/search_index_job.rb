class SearchIndexJob < ApplicationJob
  queue_as :search

  def perform(class_name, id)
    record = class_name.constantize.find_by(id: id)
    return unless record

    Pito::Search.engine.index(record)
  rescue StandardError
    nil
  end
end
