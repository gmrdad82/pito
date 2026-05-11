require "rails_helper"

# Phase 7.5 §11i — selective system spec (architect.md §D point 10).
#
# Critical user journey: a daily diff-check run finds a divergence;
# a notification surfaces; the user clicks through to the diff page;
# flips a row to accept pito; submits; the local row is preserved,
# the YouTube client receives the push, and an audit row lands.
RSpec.describe "Channel diff resolution flow", type: :system do
  before { driven_by(:rack_test) }

  let(:user)       { @auto_signed_in_user }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           title: "Local Title",
           description: "Local Description",
           youtube_connection: connection)
  end

  let(:remote_payload) do
    {
      title: "Remote Title",
      description: "Local Description", # same as local
      handle: channel.handle,
      country: channel.country,
      default_language: channel.default_language,
      keywords: channel.keywords,
      banner_url: channel.banner_url,
      avatar_url: channel.avatar_url,
      watermark_url: channel.watermark_url,
      watermark_timing: channel.watermark_timing,
      watermark_offset_ms: channel.watermark_offset_ms,
      links: channel.links,
      subscriber_count: 100,
      view_count: 1000,
      video_count: 10,
      hidden_subscriber_count: false
    }
  end

  let(:client) { instance_double(Youtube::Client) }

  before do
    allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
    allow(client).to receive(:fetch_channel).with(channel).and_return(remote_payload)
  end

  it "seeds a diff via ChannelDiffCheckJob, applies youtube-wins from the diff page" do
    # Step 1 — run the diff check inline. Open diff + notification land.
    ChannelDiffCheckJob.new.perform(channel.id)
    expect(channel.reload.open_channel_diff).to be_present
    expect(Notification.where(kind: :channel_diff_detected).count).to eq(1)

    # Step 2 — visit the diff page directly.
    visit diff_channel_path(channel)
    expect(page).to have_text("Local Title")
    expect(page).to have_text("Remote Title")

    # Step 3 — submit with the default selection (accept youtube).
    click_button "[ apply changes ]"
    expect(page).to have_current_path(channel_path(channel))
    expect(page).to have_text(/changes applied/)

    # Step 4 — verify side effects.
    channel.reload
    expect(channel.title).to eq("Remote Title")
    expect(channel.open_channel_diff).to be_nil
  end

  it "applies pito-wins by flipping the radio + invoking the YouTube push" do
    # The remote_payload above only diffs on title; flipping the
    # title radio to `accept pito` triggers a single-field push.
    push_client = instance_double(Youtube::Client)
    allow(Youtube::Client).to receive(:new).with(connection).and_return(client, push_client)
    allow(push_client).to receive(:update_channel)

    ChannelDiffCheckJob.new.perform(channel.id)

    visit diff_channel_path(channel)
    choose("decision_title_pito")

    expect(push_client).to receive(:update_channel).with(
      anything, hash_including(title: "Local Title")
    )

    click_button "[ apply changes ]"

    expect(page).to have_text(/pushed to youtube/)
    expect(channel.reload.title).to eq("Local Title")
    expect(channel.title_changed_at).to be_present
    expect(ChannelChangeLog.where(channel: channel, field: "title").count).to eq(1)
  end
end
