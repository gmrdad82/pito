require "rails_helper"

# Phase 12 — system-level coverage of the pre-publish checklist flow.
#
# Capybara's rack_test driver doesn't run JS, so the
# Stimulus-disabled-until-checked behaviour is exercised in the
# request specs (defense-in-depth on the server). These system specs
# cover the rendered surface end-to-end: editing on already-public
# videos does NOT fire the modal, the imported indicator renders,
# and the [publish] / [unpublish] CTAs follow privacy_status.
RSpec.describe "Video pre-publish checklist", type: :system do
  before { driven_by(:rack_test) }

  let(:user) { User.first || create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) { create(:channel, youtube_connection: connection) }

  it "shows the modal heading + four checkboxes for a private draft" do
    video = create(:video, channel: channel, title: "draft", category_id: "20")

    visit pre_publish_checklist_video_path(video, target_action: "publish")
    expect(page).to have_content("pre-publish checklist")
    expect(page).to have_field("video_pre_publish_game_ok", type: "checkbox")
    expect(page).to have_field("video_pre_publish_age_ok", type: "checkbox")
    expect(page).to have_field("video_pre_publish_paid_promotion_ok", type: "checkbox")
    expect(page).to have_field("video_pre_publish_end_screen_ok", type: "checkbox")
  end

  it "schedule modal includes the publish_at input" do
    video = create(:video, channel: channel, title: "draft", category_id: "20")
    visit pre_publish_checklist_video_path(video, target_action: "schedule")
    expect(page).to have_field("video_publish_at")
  end

  it "edit form on a private draft shows [publish] and [schedule] CTAs" do
    video = create(:video, channel: channel, title: "draft", category_id: "20")
    visit edit_video_path(video)
    expect(page).to have_link("[publish]")
    expect(page).to have_link("[schedule]")
  end

  it "edit form on a public video shows [unpublish] (no [publish])" do
    public_video = create(:video, :public, channel: channel)
    visit edit_video_path(public_video)
    expect(page).not_to have_link("[publish]")
    expect(page).to have_button("[unpublish]")
  end

  it "renders the imported indicator on imported videos" do
    imported = create(:video, :imported, channel: channel)
    visit video_path(imported)
    expect(page).to have_content("imported")
  end

  it "shows last_sync_error inline on the show page" do
    err_video = create(:video, :with_sync_error, channel: channel)
    visit video_path(err_video)
    expect(page).to have_content("youtube sync failed")
  end
end
