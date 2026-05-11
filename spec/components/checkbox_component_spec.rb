require "rails_helper"

RSpec.describe CheckboxComponent, type: :component do
  it "renders unchecked by default" do
    render_inline(described_class.new)
    expect(page).to have_css("label.md-check")
    expect(page).to have_css('input[type="checkbox"]')
    expect(page).to have_no_css('input[checked]')
    expect(page).to have_css("span.md-check-indicator")
  end

  it "renders checked when checked: true" do
    render_inline(described_class.new(checked: true))
    expect(page).to have_css('input[type="checkbox"][checked]')
  end

  it "renders with a label as muted text" do
    render_inline(described_class.new(label: "sync"))
    expect(page).to have_css("span.md-check-label", text: "sync")
  end

  it "renders without label span when no label" do
    render_inline(described_class.new)
    expect(page).to have_no_css("span.md-check-label")
  end

  it "renders with a value" do
    render_inline(described_class.new(value: 42))
    expect(page).to have_css('input[value="42"]')
  end

  it "renders with a name" do
    render_inline(described_class.new(name: "selected[]"))
    expect(page).to have_css('input[name="selected[]"]')
  end

  it "passes data attributes to the input" do
    render_inline(described_class.new(data: { action: "change->ctrl#toggle", bulk_select_target: "checkbox" }))
    expect(page).to have_css('input[data-action="change->ctrl#toggle"]')
    expect(page).to have_css('input[data-bulk-select-target="checkbox"]')
  end

  it "renders disabled when disabled: true" do
    render_inline(described_class.new(disabled: true))
    expect(page).to have_css('input[type="checkbox"][disabled]')
  end

  it "renders enabled (no disabled attribute) by default" do
    render_inline(described_class.new)
    expect(page).to have_no_css('input[disabled]')
  end

  it "combines all options" do
    render_inline(described_class.new(
      label: "select all",
      checked: true,
      value: "all",
      name: "items",
      data: { action: "change->bulk#toggleAll" }
    ))
    expect(page).to have_css("label.md-check")
    expect(page).to have_css('input[type="checkbox"][checked][value="all"][name="items"][data-action="change->bulk#toggleAll"]')
    expect(page).to have_css("span.md-check-indicator")
    expect(page).to have_css("span.md-check-label", text: "select all")
  end
end
