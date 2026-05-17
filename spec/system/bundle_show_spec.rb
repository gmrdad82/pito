require "rails_helper"

# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Capybara smoke for
# the bundle show page. After the 2026-05-17 simplification the
# `[seed from igdb]` button is gone (along with the columns that fed
# it), so the corresponding scenario is removed.
#
# Capybara's rack_test driver doesn't run Stimulus / JS, so this spec
# covers the rendered surface end-to-end: composite cover placeholder,
# member add via the form (server-side dispatch), member remove via
# the inline [remove] button.
RSpec.describe "Bundle show", type: :system do
  before { driven_by(:rack_test) }

  let(:bundle) { create(:bundle, name: "Soulslikes") }
  let!(:game)  { create(:game, :synced, title: "Sekiro") }

  it "renders the placeholder when no composite cover exists" do
    visit bundle_path(bundle)
    expect(page).to have_content("Soulslikes")
    expect(page).to have_content("[no cover]")
    expect(page).to have_content("no members yet.")
  end

  it "supports adding a member through the form" do
    visit bundle_path(bundle)
    select "Sekiro", from: "game_id"
    click_button "add"

    expect(bundle.reload.bundle_members.count).to eq(1)
    expect(page).to have_content("Sekiro")
  end

  it "supports removing a member through the inline button" do
    bundle.bundle_members.create!(game: game)
    visit bundle_path(bundle)
    expect(page).to have_content("Sekiro")

    click_button "remove"

    expect(bundle.reload.bundle_members.count).to eq(0)
    expect(page).to have_content("no members yet.")
  end
end
