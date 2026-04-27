require "rails_helper"

RSpec.describe SortableHeaderComponent, type: :component do
  it "renders a sortable th" do
    render_inline(described_class.new(label: "title", sort_type: "string"))
    expect(page).to have_css("th.sortable", text: "title")
    expect(page).to have_css('th[data-sort-type="string"]')
    expect(page).to have_css('th[data-action="click->sortable-table#sort"]')
  end

  it "adds num class when numeric" do
    render_inline(described_class.new(label: "views", sort_type: "number", numeric: true))
    expect(page).to have_css("th.sortable.num", text: "views")
  end

  it "omits num class when not numeric" do
    render_inline(described_class.new(label: "title", sort_type: "string"))
    expect(page).to have_no_css("th.num")
  end
end
