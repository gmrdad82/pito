require "rails_helper"

RSpec.describe Tui::ActionButtonComponent, type: :component do
  let(:base_args) { { action_name: :reindex_meilisearch, label: "reindex" } }

  it "renders a bracketed button with the label" do
    render_inline(described_class.new(**base_args))
    expect(page).to have_css("button.bracketed[type='button']")
    expect(page).to have_css("button .bl", text: "reindex")
    expect(page).to have_text("[reindex]")
  end

  it "wires the action-trigger Stimulus controller + dispatch action" do
    render_inline(described_class.new(**base_args))
    expect(page).to have_css("button[data-controller='action-trigger']")
    expect(page).to have_css("button[data-action='click->action-trigger#dispatch']")
    expect(page).to have_css("button[data-action-name='reindex_meilisearch']")
  end

  it "emits focusable attrs when focusable: passed" do
    render_inline(described_class.new(**base_args, focusable: { key: "reindex", style: :action }))
    expect(page).to have_css("button[data-tui-focusable='reindex']")
    expect(page).to have_css("button[data-tui-focusable-style='action']")
  end

  it "omits focusable attrs when focusable: nil" do
    render_inline(described_class.new(**base_args, focusable: nil))
    expect(page).not_to have_css("button[data-tui-focusable]")
    expect(page).not_to have_css("button[data-tui-focusable-style]")
  end

  it "passes extra data attrs through (snake_case → kebab-case)" do
    render_inline(described_class.new(**base_args, data: { reindex_brand: "meilisearch" }))
    expect(page).to have_css("button[data-reindex-brand='meilisearch']")
  end

  it "does NOT carry text-danger (confirmation dialog gates destructive actions)" do
    render_inline(described_class.new(**base_args))
    expect(page).not_to have_css("button.text-danger")
  end
end
