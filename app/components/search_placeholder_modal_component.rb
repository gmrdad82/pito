class SearchPlaceholderModalComponent < ViewComponent::Base
  def initialize(modal_id: "search_placeholder")
    @modal_id = modal_id
  end

  attr_reader :modal_id
end
