require "rails_helper"

# Phase 22 §11 — End-to-end happy path for the `[import]` modal on
# `/videos`.
#
# Uses rack_test (HTTP-only). The Sidekiq job side is exercised by a
# direct `Channel::ImportVideosJob.new.perform` call after the enqueue
# so the spec runs deterministically without Turbo Stream broadcasts.
RSpec.describe "Video import flow", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { driven_by(:rack_test) }

  let(:connection) { create(:youtube_connection) }
  let!(:channel_a) { create(:channel, youtube_connection: connection, title: "Channel A") }
  let!(:channel_b) { create(:channel, youtube_connection: connection, title: "Channel B") }

  # Tiny fixture client: returns a single page of items per channel.
  class StubClient
    def initialize(pages_by_channel:)
      @pages = pages_by_channel
    end

    def uploads_playlist_id(channel:)
      "UU-#{channel.id}"
    end

    def list_page(playlist_id:, page_token: nil)
      channel_id = playlist_id.sub("UU-", "").to_i
      page = (@pages[channel_id] || []).shift
      page || { items: [], next_page_token: nil }
    end
  end

  it "opens [import], picks 2 channels, completes per channel, and tombstones rejected videos" do
    stub_pages = {
      channel_a.id => [ { items: [
        { youtube_video_id: "aaaaaaaaaaa", title: "A-1" },
        { youtube_video_id: "bbbbbbbbbbb", title: "A-2" }
      ], next_page_token: nil } ],
      channel_b.id => [ { items: [
        { youtube_video_id: "ccccccccccc", title: "B-1" }
      ], next_page_token: nil } ]
    }
    fake_client = StubClient.new(pages_by_channel: stub_pages)
    allow_any_instance_of(Channels::VideoImporter).to receive(:default_playlist_client).and_return(fake_client)

    # 1. /videos shows [import]
    visit "/videos"
    expect(page).to have_content("import")

    # 2. Open the modal (rack_test follows the GET). 2026-05-11 redesign
    #    swapped the inner `[videos] · [import]` pseudo-breadcrumb for
    #    a real `[videos] / [import channels]` breadcrumb plus a single
    #    `<h1>import channels</h1>` heading. Assert all three pieces
    #    along with the tagline.
    visit "/imports/channels"
    expect(page).to have_content("pick the channels to pull new uploads from")
    expect(page).to have_css("h1", text: "import channels")
    expect(page).to have_content("[videos]")
    expect(page).to have_content("[import channels]")
    # The "no videos yet." note on the underlying /videos page was
    # dropped — it used to bleed through underneath the modal.
    expect(page).not_to have_content("no videos yet")

    # 3. Submit the form with both channels ticked. Capybara's
    #    rack_test driver lets us drive the form fields directly.
    expect {
      page.driver.submit :post, "/imports/channels",
                          { "channel_ids[]" => [ channel_a.id, channel_b.id ] }
    }.to change(ImportJob, :count).by(2)
      .and change(Channel::ImportVideosJob.jobs, :size).by(2)

    job_a = ImportJob.find_by!(channel: channel_a)
    job_b = ImportJob.find_by!(channel: channel_b)

    # 4. Run both Sidekiq jobs inline.
    Channel::ImportVideosJob.new.perform(channel_a.id, job_a.id)
    Channel::ImportVideosJob.new.perform(channel_b.id, job_b.id)

    expect(job_a.reload.status).to eq("completed")
    expect(job_b.reload.status).to eq("completed")
    expect(channel_a.videos.count).to eq(2)
    expect(channel_b.videos.count).to eq(1)

    # 5. Open job_a's keep/reject screen.
    visit "/imports/channels/#{job_a.id}"
    expect(page).to have_content("keep what to import")
    expect(page).to have_content("A-1")
    expect(page).to have_content("A-2")

    # 6. Uncheck `A-2`; submit `[keep]` with only `A-1`'s id.
    a_keep = channel_a.videos.find_by!(youtube_video_id: "aaaaaaaaaaa")
    a_reject = channel_a.videos.find_by!(youtube_video_id: "bbbbbbbbbbb")

    expect {
      page.driver.submit :patch, "/imports/channels/#{job_a.id}",
                          { "keep_video_ids[]" => [ a_keep.id ] }
    }.to change(RejectedVideoImport, :count).by(1)
      .and change(Video, :count).by(-1)

    expect(Video.where(id: a_keep.id)).to exist
    expect(Video.where(id: a_reject.id)).not_to exist
    tombstone = RejectedVideoImport.find_by!(channel: channel_a,
                                             youtube_video_id: "bbbbbbbbbbb")
    expect(tombstone.rejected_by).to eq(User.first)

    # 7. Re-import on channel A — the rejected video stays rejected.
    Rails.cache.clear
    expect {
      page.driver.submit :post, "/imports/channels",
                          { "channel_ids[]" => [ channel_a.id ] }
    }.to change(ImportJob, :count).by(1)

    new_job_a = ImportJob.where(channel: channel_a).order(:created_at).last
    # Replenish the stub for the next pass.
    stub_pages[channel_a.id] = [ { items: [
      { youtube_video_id: "aaaaaaaaaaa", title: "A-1" },
      { youtube_video_id: "bbbbbbbbbbb", title: "A-2" }
    ], next_page_token: nil } ]
    Channel::ImportVideosJob.new.perform(channel_a.id, new_job_a.id)

    new_job_a.reload
    expect(new_job_a.status).to eq("completed")
    # The rejected id should NOT have been re-imported (already kept
    # A-1 exists; B was tombstoned). Imported delta = 0.
    expect(new_job_a.imported_videos).to eq(0)
    expect(Video.where(youtube_video_id: "bbbbbbbbbbb")).not_to exist
  end
end
