module Searchable
  extend ActiveSupport::Concern

  class_methods do
    def searchable_fields
      @searchable_fields || []
    end

    def filterable_fields
      @filterable_fields || []
    end

    private

    def searchable(*fields)
      @searchable_fields = fields
    end

    def filterable(*fields)
      @filterable_fields = fields
    end
  end

  included do
    after_commit :search_index, on: [ :create, :update ]
  end

  private

  def search_index
    SearchIndexJob.perform_later(self.class.name, id)
  end
end
