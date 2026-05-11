require "rails_helper"

# Phase 23 — selective system spec (architect.md §D point 10).
#
# Critical user journey: a daily diff-check run finds a divergence;
# a notification surfaces; the user clicks through to the diff page;
# flips a row to accept pito; submits; the local row is preserved,
# the YouTube client receives the push, and an audit row lands.
RSpec.describe "Video sync + diff flow", type: :system do
  before { driven_by(:rack_test) }

  let(:user) { @auto_signed_in_user }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: connection)
  end
  let(:video) do
    create(:video, channel: channel, title: "local title",
                   description: "local body",
                   duration_seconds: 60,
                   embeddable: true, public_stats_viewable: true,
                   thumbnail_url: "https://i.ytimg.com/vi/abc/maxres.jpg",
                   self_declared_made_for_kids: false,
                   contains_synthetic_media: false,
                   view_count: 0, like_count: 0, comment_count: 0)
  end

  let(:remote_payload_with_title_diff) do
    {
      items: [
        {
          snippet: { title: "remote title", description: video.description,
                     tags: [], categoryId: video.category_id,
                     thumbnails: { maxres: { url: video.thumbnail_url } } },
          status: { privacyStatus: "private", publishAt: nil,
                    embeddable: true, publicStatsViewable: true,
                    selfDeclaredMadeForKids: false,
                    containsSyntheticMedia: false,
                    madeForKids: false },
          statistics: { viewCount: "0", likeCount: "0", commentCount: "0" },
          contentDetails: { duration: "PT1M" }
        }
      ]
    }
  end

  let(:client_double) { instance_double(Youtube::Client) }

  before do
    allow(Youtube::Client).to receive(:new).with(connection).and_return(client_double)
    allow(client_double).to receive(:videos_list).and_return(remote_payload_with_title_diff)
  end

  it "seeds a diff via VideoDiffCheckJob, lands on the diff page from /videos/:slug, and applies youtube-wins" do
    # Step 1 — run the diff check job inline. Open diff + notification land.
    VideoDiffCheckJob.new.perform(video.id)
    expect(video.reload.open_diff).to be_present
    expect(Notification.where(kind: :video_diff_detected).count).to eq(1)

    # Step 2 — visit the video show page; the open-diff banner appears.
    visit video_path(video)
    expect(page).to have_text(/youtube diverged on 1 field/)

    # Step 3 — click [ view diff ].
    click_link "[ view diff ]"
    expect(page).to have_current_path(diff_video_path(video))
    expect(page).to have_text("local title")
    expect(page).to have_text("remote title")

    # Step 4 — submit the form with the default (accept youtube).
    click_button "[ apply changes ]"
    expect(page).to have_current_path(video_path(video))
    expect(page).to have_text(/diff resolved/)

    # Step 5 — verify side effects.
    video.reload
    expect(video.title).to eq("remote title")
    expect(video.open_diff).to be_nil
    expect(VideoChangeLog.where(video: video, source: :youtube_pull, field: "title").count).to eq(1)
  end

  it "applies pito-wins by flipping the radio + invoking the YouTube push" do
    reader_double = instance_double(Youtube::VideosReader,
                                    read_video: { snippet: { title: "remote title" },
                                                  status: { privacyStatus: "private" } })
    push_client = instance_double(Youtube::VideosClient, update_video: { id: video.youtube_video_id })
    allow(Youtube::VideosReader).to receive(:new).and_return(reader_double)
    allow(Youtube::VideosClient).to receive(:new).and_return(push_client)

    expect(push_client).to receive(:update_video).with(
      anything, hash_including(:fresh, fields: [ :title ])
    )

    VideoDiffCheckJob.new.perform(video.id)

    visit diff_video_path(video)
    # Override the default selection.
    choose("decision_title_pito")
    click_button "[ apply changes ]"

    expect(page).to have_text(/pushed to youtube/)
    expect(video.reload.title).to eq("local title")
    expect(video.title_changed_at).to be_present
    expect(VideoChangeLog.where(video: video, source: :pito_apply, field: "title").count).to eq(1)
  end
end
