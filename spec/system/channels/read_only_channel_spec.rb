require "rails_helper"

# Unit A0 — channel read-only conversion.
#
# The channel is a strictly one-way, read-only mirror (YouTube → pito).
# This system spec proves, end-to-end, that:
#
#   1. The channel edit surface is gone — visiting `/channels/:id/edit`
#      does not render an edit form.
#   2. The channel show page carries no edit affordance and no
#      diff-reconciliation banner.
#   3. The one mutable channel attribute — `star` — still toggles
#      end-to-end via the inline pane form (the new
#      `channel_star_path` write path).
RSpec.describe "Channel read-only mirror", type: :system do
  before do
    driven_by(:rack_test)
    ChannelSync.clear
  end

  let!(:channel) do
    create(:channel, title: "Read Only Channel", handle: "@readonly")
  end

  it "does not render an edit form at /channels/:id/edit" do
    # The edit route was removed; `/channels/<slug>/edit` matches no
    # route at all (the greedy `/channels/:id` member route does not
    # span path separators). The rack_test driver surfaces the
    # `ActionController::RoutingError` directly on `visit`. Either way,
    # the contract is: no edit form is ever rendered.
    rendered_edit_form = false
    begin
      visit "/channels/#{channel.to_param}/edit"
      rendered_edit_form =
        page.has_field?("channel[title]") ||
        page.has_field?("channel[description]") ||
        page.has_button?("update")
    rescue ActionController::RoutingError, ActionView::Template::Error
      # No route — the edit surface is gone. This is the expected path.
    end

    expect(rendered_edit_form).to be(false)
  end

  it "renders the show page with no edit affordance and no diff banner" do
    visit channel_path(channel)

    expect(page).to have_selector("h1", text: "Read Only Channel")
    expect(page).not_to have_link(text: /\bedit\b/i)
    expect(page.html).not_to match(%r{/channels/[^"]+/edit})
    expect(page.html).not_to include("channel_diff_banner")
  end

  describe "the [star] / [unstar] toggle on a channel pane" do
    # The pane view renders only with two or more ids in the workspace.
    let!(:sibling) { create(:channel, title: "Sibling Channel") }

    it "stars an unstarred channel from the pane and persists" do
      visit "#{panes_channels_path}?ids=#{channel.id},#{sibling.id}"

      # The target channel's pane shows `[star]` (it is unstarred).
      expect(page).to have_button("[star]")

      # Click the first `[star]` button — the target channel's pane is
      # rendered first (ids ordering).
      first(:button, "[star]").click

      # The form PATCHes channel_star_path and redirects back to the
      # channel show page with the star flipped.
      expect(channel.reload.star).to be(true)
    end

    it "unstars a starred channel from the pane and persists" do
      channel.update_columns(star: true)
      visit "#{panes_channels_path}?ids=#{channel.id},#{sibling.id}"

      expect(page).to have_button("[unstar]")
      first(:button, "[unstar]").click

      expect(channel.reload.star).to be(false)
    end
  end
end
