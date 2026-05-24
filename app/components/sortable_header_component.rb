# Sortable column header for client-side `sortable_table_controller`.
#
# Emits a `<th>` carrying the canonical TUI table primitive classes
# (`tui-table__th` + `--left` / `--right`) plus `sortable` + optional
# `num` for numeric columns. The shared V4 underline rules
# (`th.sortable.sort-asc` / `.sort-desc`) paint the active-sort
# indicator the same way they paint the sessions table's
# `sort_link_to` headers — visual parity across both rendering shapes.
class SortableHeaderComponent < ViewComponent::Base
  def initialize(label:, sort_type:, numeric: false, extra_class: nil)
    @label = label
    @sort_type = sort_type
    @numeric = numeric
    @extra_class = extra_class
  end

  def css_classes
    classes = [ "tui-table__th" ]
    classes << (@numeric ? "tui-table__th--right" : "tui-table__th--left")
    classes << "sortable"
    classes << "num" if @numeric
    classes << @extra_class if @extra_class.present?
    classes.join(" ")
  end
end
