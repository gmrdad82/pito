class ReindexAllJob < ApplicationJob
  queue_as :search

  def perform
    engine = Search.engine
    [ Channel, Video ].each do |model|
      engine.reindex_all(model)
    end
  end
end
