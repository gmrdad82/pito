require "rails_helper"

RSpec.describe Tui::PanelFieldsetComponent, type: :component do
  it "wraps content in <fieldset class='tui-panel-fieldset'>" do
    render_inline(described_class.new) { "inner content" }
    expect(page).to have_css("fieldset.tui-panel-fieldset", text: "inner content")
  end

  it "appends class_name when provided" do
    render_inline(described_class.new(class_name: "custom")) { "x" }
    expect(page).to have_css("fieldset.tui-panel-fieldset.custom")
  end

  it "renders without crashing when content is empty" do
    expect { render_inline(described_class.new) { } }.not_to raise_error
  end

  it "carries no inline style" do
    render_inline(described_class.new) { "x" }
    expect(page).not_to have_css("fieldset[style]")
  end

  it "applies data attributes when provided" do
    render_inline(described_class.new(data: { controller: "sessions-bulk-revoke" })) { "x" }
    expect(page).to have_css("fieldset[data-controller='sessions-bulk-revoke']")
  end
end
