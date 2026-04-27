require "rails_helper"

RSpec.describe SavedViewsSectionComponent, type: :component do
  it "does not render when no saved views" do
    render_inline(described_class.new(saved_views: SavedView.none, kind: "channels"))
    expect(page.text).to be_blank
  end

  it "renders saved views with open and delete links" do
    view = create(:saved_view, kind: :channels, url: "/channels/1", name: "my channel")
    render_inline(described_class.new(saved_views: SavedView.channels.ordered, kind: "channels"))

    expect(page).to have_css("h2", text: "saved views")
    expect(page).to have_link("[ open ]", href: "/channels/1")
    expect(page).to have_css("a.text-danger")
    expect(page).to have_css("dialog")
  end

  it "shows display name with deletions" do
    channel = create(:channel, title: "Test Channel")
    view = create(:saved_view, kind: :channels, url: "/channels/panes?ids=#{channel.id},99999", name: "mixed")
    render_inline(described_class.new(saved_views: SavedView.channels.ordered, kind: "channels"))

    expect(page).to have_text("Test Channel")
    expect(page).to have_text("[deleted]")
  end
end
