class SavedViewsSectionComponent < ViewComponent::Base
  def initialize(saved_views:, kind:)
    @saved_views = saved_views
    @kind = kind
  end

  def render?
    @saved_views.any?
  end
end
