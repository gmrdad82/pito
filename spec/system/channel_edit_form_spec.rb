require "rails_helper"

# Phase 7.5 §11c — Channel Edit Form. ONE selective system spec
# (architect rule D — system specs are critical-path only). Walks
# the description-edit happy path end-to-end against a rack_test
# driver: open edit page → fill description → submit → land on
# show page with new description rendered.
#
# WebMock stubs the underlying Google::Apis::YoutubeV3::YouTubeService
# so no real network traffic fires; the spec exercises the controller
# dispatch + service layer + view layer in one pass.
RSpec.describe "Channel edit form", type: :system do
  let(:connection) { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcabcabcabcabcabcabcA",
           title: "Cached title",
           description: "Old cached description",
           country: "US",
           default_language: "en",
           youtube_connection: connection)
  end

  before do
    driven_by(:rack_test)
    # Stub the YouTube client at the call site — we are exercising
    # the form + controller, not the API. The service spec covers the
    # destructive PUT plumbing in isolation.
    fake_client = instance_double(
      Youtube::Client,
      update_channel: { title: "Cached title", description: "Brand new description" }
    )
    allow(Youtube::Client).to receive(:new).and_return(fake_client)
  end

  it "happy path — edit description, submit, land on show with new description" do
    visit edit_channel_path(channel)

    expect(page).to have_content("edit channel")
    expect(page).to have_field("channel[description]", with: "Old cached description")

    fill_in "channel[description]", with: "Brand new description"
    click_button "[update]"

    expect(page).to have_current_path(channel_path(channel))
    expect(page).to have_content("channel updated.")
    expect(channel.reload.description).to eq("Brand new description")
  end
end
