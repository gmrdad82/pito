require "rails_helper"

# Phase 24 — critical user journey for the per-channel `[revoke]` flow.
# Selective system coverage per the project's spec pyramid: one happy
# path scenario, no sad-path / IDOR / boundary specs (those live in the
# request spec).
RSpec.describe "Channel revoke", type: :system do
  before do
    driven_by(:rack_test)
    Sidekiq::Testing.fake!
    ChannelSync.clear
  end

  let(:connection) { create(:youtube_connection) }
  let!(:channel) { create(:channel, youtube_connection: connection, title: "Sample") }

  it "happy path — channel show → [revoke] → confirm → /channels with flash + job enqueued" do
    visit channel_path(channel)
    expect(page).to have_link("[revoke]")

    click_link "[revoke]"
    expect(page).to have_content('revoke channel "Sample"?')
    expect(page).to have_button("[confirm revoke]")

    expect {
      click_button "[confirm revoke]"
    }.to change(DeleteChannelDataJob.jobs, :size).by(1)

    expect(page).to have_current_path(channels_path)
    expect(page).to have_content("channel revoke scheduled")

    job = DeleteChannelDataJob.jobs.last
    expect(job["args"]).to eq([ channel.id, connection.id ])
  end

  it "[cancel] from the modal returns to the channel show without enqueueing" do
    visit channel_path(channel)
    click_link "[revoke]"

    expect {
      click_link "[cancel]"
    }.not_to change(DeleteChannelDataJob.jobs, :size)

    expect(page).to have_current_path(channel_path(channel))
  end
end
