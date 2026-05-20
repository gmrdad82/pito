require "rails_helper"

RSpec.describe Tui::SubPanelComponent, type: :component do
  it "renders a .pito-sub-panel wrapper with title" do
    render_inline(described_class.new(title: "Redis")) { "content here" }
    expect(page).to have_css("div.pito-sub-panel")
    expect(page).to have_css(".pito-sub-panel__title", text: "Redis")
    expect(page).to have_text("content here")
  end

  it "renders actions slot when provided" do
    render_inline(described_class.new(title: "Meilisearch")) do |c|
      c.with_actions { "[reindex]" }
      "body"
    end
    expect(page).to have_css(".pito-sub-panel__actions", text: "[reindex]")
  end

  it "omits actions span when no actions provided" do
    render_inline(described_class.new(title: "assets")) { "body" }
    expect(page).not_to have_css(".pito-sub-panel__actions")
  end

  it "appends class_name when provided" do
    render_inline(described_class.new(title: "x", class_name: "custom")) { "body" }
    expect(page).to have_css(".pito-sub-panel.custom")
  end

  it "renders without crashing when content is empty" do
    expect { render_inline(described_class.new(title: "empty")) }.not_to raise_error
  end

  it "carries no inline style" do
    render_inline(described_class.new(title: "x")) { "y" }
    expect(page).not_to have_css(".pito-sub-panel[style]")
  end
end
