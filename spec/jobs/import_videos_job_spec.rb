# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportVideosJob do
  let(:connection) { create(:youtube_connection) }
  let!(:channel) {
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCaaa111",
           title: "Alpha Channel",
           handle: "@alpha")
  }

  let(:conversation) { Conversation.create! }
  let(:turn) {
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/connect"
    )
  }

  before do
    allow_any_instance_of(Channel::Youtube::Client).to receive(:channels_list).and_return(
      {
        items: [
          {
            content_details: {
              related_playlists: {
                uploads: "UUaaa111"
              }
            }
          }
        ]
      }
    )

    allow_any_instance_of(Channel::Youtube::Client).to receive(:playlist_items_list).and_return(
      {
        items: [
          {
            snippet: {
              resource_id: { video_id: "video123" },
              title: "Video One"
            }
          },
          {
            snippet: {
              resource_id: { video_id: "video456" },
              title: "Video Two"
            }
          }
        ],
        next_page_token: nil
      }
    )

    allow_any_instance_of(Channel::Youtube::Client).to receive(:videos_list).and_return(
      {
        items: [
          {
            id: "video123",
            snippet: {
              title: "Video One",
              description: "First video",
              published_at: "2024-01-01T00:00:00Z",
              thumbnails: { high: { url: "https://example.com/thumb1.jpg" } },
              tags: [ "gaming", "rpg" ],
              category_id: "20"
            },
            statistics: {
              view_count: "1000",
              like_count: "50",
              comment_count: "10"
            },
            content_details: {
              duration: "PT10M30S"
            },
            status: {
              privacy_status: "public"
            },
            etag: "etag123"
          },
          {
            id: "video456",
            snippet: {
              title: "Video Two",
              description: "Second video",
              published_at: "2024-02-01T00:00:00Z",
              thumbnails: { high: { url: "https://example.com/thumb2.jpg" } },
              tags: [ "action" ],
              category_id: "20"
            },
            statistics: {
              view_count: "500",
              like_count: "25",
              comment_count: "5"
            },
            content_details: {
              duration: "PT5M"
            },
            status: {
              privacy_status: "private",
              publish_at: "2025-01-01T00:00:00Z"
            },
            etag: "etag456"
          }
        ]
      }
    )
  end

  it "creates Video records for each video" do
    expect {
      described_class.new.perform(connection.id, turn.id)
    }.to change(Video, :count).by(2)
  end

  it "stores correct video attributes" do
    described_class.new.perform(connection.id, turn.id)

    video = Video.find_by(youtube_video_id: "video123")
    expect(video.title).to eq("Video One")
    expect(video.description).to eq("First video")
    expect(video.duration_seconds).to eq(630) # 10m30s
    expect(Pito::Stats.get(video, :views)).to eq(1000) # P4 — via stats table
    expect(video.like_count).to eq(50)
    expect(video.comment_count).to eq(10)
    expect(video.privacy_status).to eq("public")
    expect(video.thumbnail_url).to eq("https://example.com/thumb1.jpg")
    expect(video.tags).to eq([ "gaming", "rpg" ])
    expect(video.category_id).to eq("20")
    expect(video.etag).to eq("etag123")
    expect(video.channel).to eq(channel)
  end

  it "handles scheduled videos with publish_at" do
    described_class.new.perform(connection.id, turn.id)

    video = Video.find_by(youtube_video_id: "video456")
    expect(video.privacy_status).to eq("private")
    expect(video.publish_at).to be_present
  end

  it "updates channel last_synced_at" do
    described_class.new.perform(connection.id, turn.id)
    expect(channel.reload.last_synced_at).to be_within(5.seconds).of(Time.current)
  end

  it "emits an enhanced event with video breakdown" do
    described_class.new.perform(connection.id, turn.id)

    event = conversation.events.where(kind: :enhanced).last
    expect(event.payload["body"]).to include("Videos total")
    expect(event.payload["body"]).to include("Published")
    expect(event.payload["body"]).to include("Scheduled")
    expect(event.payload["body"]).to include("Unlisted")
    expect(event.payload["body"]).to include("Drafts")
  end

  it "resolves the thinking indicator" do
    thinking = Event.create_with_position!(
      conversation: conversation,
      turn: turn,
      kind: :thinking,
      payload: { dictionary: "importing", word_index: 0, started_at: 5.seconds.ago.iso8601 }
    )

    described_class.new.perform(connection.id, turn.id)

    thinking.reload
    expect(thinking.payload["resolved"]).to be(true)
    expect(thinking.payload["elapsed_seconds"]).to be >= 4
  end

  it "handles DateTime values from the API client (not just strings)" do
    # The YouTube client's symbolize_struct passes DateTime objects through
    # unchanged; parse_time must not crash on them.
    allow_any_instance_of(Channel::Youtube::Client).to receive(:videos_list).and_return(
      {
        items: [
          {
            id: "video789",
            snippet: {
              title: "Video Three",
              description: "Third video",
              published_at: DateTime.new(2024, 3, 1, 12, 0, 0), # DateTime, not String
              thumbnails: { high: { url: "https://example.com/thumb3.jpg" } },
              tags: [],
              category_id: "20"
            },
            statistics: {
              view_count: "300",
              like_count: "15",
              comment_count: "3"
            },
            content_details: {
              duration: "PT2M"
            },
            status: {
              privacy_status: "private",
              publish_at: DateTime.new(2025, 4, 1, 10, 0, 0) # DateTime, not String
            },
            etag: "etag789"
          }
        ]
      }
    )

    described_class.new.perform(connection.id, turn.id)

    video = Video.find_by(youtube_video_id: "video789")
    expect(video).to be_present
    expect(video.published_at).to be_within(1.second).of(Time.utc(2024, 3, 1, 12, 0, 0))
    expect(video.publish_at).to be_within(1.second).of(Time.utc(2025, 4, 1, 10, 0, 0))
  end

  it "marks the turn as completed" do
    described_class.new.perform(connection.id, turn.id)

    turn.reload
    expect(turn.completed_at).to be_present
  end

  it "no-ops when turn is already completed" do
    turn.update!(completed_at: Time.current)

    expect {
      described_class.new.perform(connection.id, turn.id)
    }.not_to change { conversation.events.count }
  end

  it "no-ops when connection is missing" do
    expect {
      described_class.new.perform(0, turn.id)
    }.not_to change { conversation.events.count }
  end

  context "with empty playlist" do
    before do
      allow_any_instance_of(Channel::Youtube::Client).to receive(:playlist_items_list).and_return(
        { items: [], next_page_token: nil }
      )
    end

    it "creates no videos but still emits breakdown and completes turn" do
      expect {
        described_class.new.perform(connection.id, turn.id)
      }.not_to change(Video, :count)

      turn.reload
      expect(turn.completed_at).to be_present

      event = conversation.events.where(kind: :enhanced).last
      expect(event.payload["body"]).to include("0")
    end
  end

  context "with missing uploads playlist" do
    before do
      allow_any_instance_of(Channel::Youtube::Client).to receive(:channels_list).and_return(
        { items: [ { content_details: {} } ] }
      )
    end

    it "returns early but still completes the turn" do
      expect {
        described_class.new.perform(connection.id, turn.id)
      }.not_to change(Video, :count)

      turn.reload
      expect(turn.completed_at).to be_present
    end
  end
end
