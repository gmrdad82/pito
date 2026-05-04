require "rails_helper"

RSpec.describe SavedViewsSectionComponent, type: :component do
  it "does not render when no saved views" do
    render_inline(described_class.new(saved_views: SavedView.none, kind: "channels"))
    expect(page.text).to be_blank
  end

  it "renders saved views with open and delete links" do
    create(:saved_view, kind: :channels, url: "/channels/1", name: "my channel")
    render_inline(described_class.new(saved_views: SavedView.channels.ordered, kind: "channels"))

    expect(page).to have_css("h2", text: "saved views")
    expect(page).to have_link("[open]", href: "/channels/1")
    expect(page).to have_css("a.text-danger")
    expect(page).to have_css("dialog")
  end

  it "renders a confirm modal for each saved view, with no data-turbo-confirm" do
    view = create(:saved_view, kind: :channels, url: "/channels/1", name: "my channel")
    render_inline(described_class.new(saved_views: SavedView.channels.ordered, kind: "channels"))

    expect(page).to have_css("dialog.confirm-modal##{"confirm-saved-view-#{view.id}"}")
    expect(page).to have_text("delete this saved view?")
    expect(page).to have_no_css("[data-turbo-confirm]")
  end

  it "wires the delete link to open the matching modal" do
    view = create(:saved_view, kind: :channels, url: "/channels/1", name: "my channel")
    render_inline(described_class.new(saved_views: SavedView.channels.ordered, kind: "channels"))

    expect(page).to have_css(
      "a.text-danger[data-controller='modal-trigger']" \
      "[data-action='click->modal-trigger#open']" \
      "[data-modal-trigger-target-id-value='confirm-saved-view-#{view.id}']"
    )
  end

  it "wraps the rows in a saved-views-list flex container (Phase 4 §9.3)" do
    create(:saved_view, kind: :channels, url: "/channels/1", name: "my channel")
    render_inline(described_class.new(saved_views: SavedView.channels.ordered, kind: "channels"))
    expect(page).to have_css(".saved-views-list .saved-views-row")
  end

  it "shows display name with deletions" do
    channel = create(:channel)
    create(:saved_view, kind: :channels, url: "/channels/panes?ids=#{channel.id},99999", name: "mixed")
    render_inline(described_class.new(saved_views: SavedView.channels.ordered, kind: "channels"))

    # Channel labels are now the channel id (Phase A → B convention).
    expect(page).to have_text(channel.id.to_s)
    expect(page).to have_text("[deleted]")
  end
end
