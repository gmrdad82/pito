class SortableHeaderComponent < ViewComponent::Base
  def initialize(label:, sort_type:, numeric: false, extra_class: nil)
    @label = label
    @sort_type = sort_type
    @numeric = numeric
    @extra_class = extra_class
  end

  def css_classes
    classes = [ "sortable" ]
    classes << "num" if @numeric
    classes << @extra_class if @extra_class.present?
    classes.join(" ")
  end
end
