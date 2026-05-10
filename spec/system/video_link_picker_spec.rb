require "rails_helper"

# Phase 14 §3 — Capybara smoke for the video edit form's link picker.
# rack_test drives without JS, so the picker's filter is not exercised
# end-to-end here; the spec verifies the server-side dispatch through
# the form-submit on each option.
RSpec.describe "Video link picker", type: :system do
  before { driven_by(:rack_test) }

  let(:channel) { create(:channel) }
  let!(:video)  { create(:video, channel: channel, title: "Let's Play Sekiro") }
  let!(:game)   { create(:game, title: "Sekiro") }
  let!(:bundle) { create(:bundle, name: "Soulslikes") }

  it "renders the empty links state" do
    visit edit_video_path(video)
    expect(page).to have_content("no links yet.")
  end

  it "adds a game link via the picker" do
    visit edit_video_path(video)
    expect(page).to have_content("[ add link ]")

    within(".link-picker") do
      # The picker renders one form per option. Click the bracketed
      # button under the row labeled with the game title.
      find("li[data-search-text='Sekiro']").click_button(match: :first)
    end

    expect(VideoGameLink.where(video: video, game: game).count).to eq(1)
    visit edit_video_path(video)
    expect(page).to have_content("Sekiro")
  end

  it "shows a link row with [remove] action-screen flow" do
    create(:video_game_link, video: video, game: game)
    visit edit_video_path(video)

    expect(page).to have_link("remove",
                              href: deletions_path(type: "video_game_link", ids: VideoGameLink.last.id))
  end

  it "rejects a duplicate link with a clean 'already linked' flash" do
    create(:video_game_link, video: video, game: game)

    visit edit_video_path(video)
    within(".link-picker") do
      find("li[data-search-text='Sekiro']").click_button(match: :first)
    end

    expect(page).to have_content("already linked.")
  end
end
