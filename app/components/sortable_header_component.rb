class SortableHeaderComponent < ViewComponent::Base
  def initialize(label:, sort_type:, numeric: false)
    @label = label
    @sort_type = sort_type
    @numeric = numeric
  end

  def css_classes
    classes = [ "sortable" ]
    classes << "num" if @numeric
    classes.join(" ")
  end
end
