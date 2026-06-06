# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelInfoJob do
  let(:conversation) { Conversation.create! }
  let(:turn) {
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/connect"
    )
  }

  let(:connection) { create(:youtube_connection) }
  let!(:channel) {
    create(:channel,
           youtube_connection: connection,
           youtube_channel_id: "UCaaa111",
           title: "Alpha Channel",
           handle: "@alpha")
  }

  before do
    allow_any_instance_of(Channel::Youtube::Client).to receive(:channels_list).and_return(
      {
        items: [
          {
            snippet: {
              title: "Alpha Channel",
              custom_url: "@alpha",
              description: "A test channel",
              thumbnails: {
                default: { url: "https://example.com/avatar.jpg" }
              }
            },
            statistics: {
              subscriber_count: "1500",
              view_count: "2300000",
              video_count: "42"
            },
            branding_settings: {
              image: {
                banner_external_url: "https://example.com/banner.jpg"
              }
            }
          }
        ]
      }
    )
  end

  it "updates channel stats from YouTube API" do
    described_class.new.perform(connection.id, turn.id)

    channel.reload
    expect(Pito::Stats.get(channel, :subscribers)).to eq(1500)
    expect(Pito::Stats.get(channel, :views)).to eq(2_300_000)
    expect(channel.video_count).to eq(42)
    expect(channel.last_synced_at).to be_within(5.seconds).of(Time.current)
  end

  it "fills in missing channel info (avatar, banner, description)" do
    described_class.new.perform(connection.id, turn.id)

    channel.reload
    expect(channel.description).to eq("A test channel")
    expect(channel.avatar_url).to eq("https://example.com/avatar.jpg")
    expect(channel.banner_url).to eq("https://example.com/banner.jpg")
  end

  it "emits an enhanced event with formatted stats" do
    expect {
      described_class.new.perform(connection.id, turn.id)
    }.to change { conversation.events.where(kind: :enhanced).count }.by(1)

    event = conversation.events.where(kind: :enhanced).last
    expect(event.payload["body"]).to include("Alpha Channel")
    expect(event.payload["body"]).to include("1.5K")  # subscribers
    expect(event.payload["body"]).to include("2.3M")  # views
  end

  it "does NOT mark the turn as completed (ImportVideosJob does that)" do
    described_class.new.perform(connection.id, turn.id)

    turn.reload
    expect(turn.completed_at).to be_nil
  end

  it "resolves the thinking indicator" do
    thinking = Event.create_with_position!(
      conversation: conversation,
      turn: turn,
      kind: :thinking,
      payload: { dictionary: "slash", word_index: 0, started_at: 5.seconds.ago.iso8601 }
    )

    described_class.new.perform(connection.id, turn.id)

    thinking.reload
    expect(thinking.payload["resolved"]).to be(true)
    expect(thinking.payload["elapsed_seconds"]).to be >= 4
  end

  it "emits a thinking indicator for video import" do
    described_class.new.perform(connection.id, turn.id)

    thinkings = conversation.events.where(kind: :thinking).order(:position)
    expect(thinkings.count).to eq(1)
    expect(thinkings.last.payload["dictionary"]).to eq("importing")
  end

  it "enqueues ImportVideosJob for stage 2" do
    expect {
      described_class.new.perform(connection.id, turn.id)
    }.to have_enqueued_job(ImportVideosJob).with(connection.id, turn.id)
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

  context "with multiple channels" do
    let!(:channel_b) {
      create(:channel,
             youtube_connection: connection,
             youtube_channel_id: "UCbbb222",
             title: "Beta Channel",
             handle: "@beta")
    }

    before do
      call_count = 0
      allow_any_instance_of(Channel::Youtube::Client).to receive(:channels_list) do |_, **kwargs|
        call_count += 1
        id = Array(kwargs[:ids]).first
        {
          items: [
            {
              snippet: {
                title: id == "UCaaa111" ? "Alpha Channel" : "Beta Channel",
                custom_url: id == "UCaaa111" ? "@alpha" : "@beta",
                description: "Test",
                thumbnails: { default: { url: "https://example.com/avatar.jpg" } }
              },
              statistics: {
                subscriber_count: id == "UCaaa111" ? "1500" : "50000",
                view_count: id == "UCaaa111" ? "2300000" : "15000000",
                video_count: id == "UCaaa111" ? "42" : "120"
              },
              branding_settings: {
                image: { banner_external_url: "https://example.com/banner.jpg" }
              }
            }
          ]
        }
      end
    end

    it "fetches stats for all channels" do
      described_class.new.perform(connection.id, turn.id)

      expect(Pito::Stats.get(channel, :subscribers)).to eq(1500)
      expect(Pito::Stats.get(channel_b, :subscribers)).to eq(50_000)
    end

    it "emits one enhanced event with all channels" do
      described_class.new.perform(connection.id, turn.id)

      event = conversation.events.where(kind: :enhanced).last
      body = event.payload["body"]
      expect(body).to include("Alpha Channel")
      expect(body).to include("Beta Channel")
      expect(body).to include("1.5K")
      expect(body).to include("50K")
    end
  end

  context "with API errors" do
    before do
      allow_any_instance_of(Channel::Youtube::Client).to receive(:channels_list).and_raise(
        Channel::Youtube::QuotaExhaustedError.new("quota exceeded")
      )
    end

    it "emits an enhanced event with the error inline and completes the turn" do
      expect {
        described_class.new.perform(connection.id, turn.id)
      }.to change { conversation.events.where(kind: :enhanced).count }.by(1)

      event = conversation.events.where(kind: :enhanced).last
      expect(event.payload["body"]).to include("quota exceeded")

      turn.reload
      expect(turn.completed_at).to be_present
    end
  end
end
