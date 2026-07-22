# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::VideoVisit do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:video) do
    create(:video, title: "Alpha Adventures", youtube_video_id: "yt_abc")
  end

  # video_visit's tools.yml `consume` entry lands in a later task — stub the
  # Matrix seam so `declared?("consume")` resolves without it (the same
  # fake-target pattern T8.4 established for targets not yet in tools.yml;
  # see spec/requests/follow_up_spec.rb).
  before do
    allow(Pito::Dispatch::Matrix).to receive(:actions_for).and_call_original
    allow(Pito::Dispatch::Matrix).to receive(:actions_for).with("video_visit").and_return([ "consume" ])
    allow(Pito::Dispatch::Matrix).to receive(:mode_for).and_call_original
    allow(Pito::Dispatch::Matrix).to receive(:mode_for).with("video_visit").and_return(:mutate)
  end

  # Minimal stand-in for the source event — the handler only reads payload.
  def event_for(video_id, extra = {})
    Struct.new(:payload).new({ "video_id" => video_id }.merge(extra))
  end

  it "registers for the video_visit target" do
    expect(described_class.target).to eq("video_visit")
  end

  it "Matrix serves :mutate mode for video_visit" do
    expect(Pito::Dispatch::Matrix.mode_for("video_visit")).to eq(:mutate)
  end

  it "is internal (must not appear as a user-typeable #hashtag or in #help)" do
    expect(described_class.internal?).to be true
  end

  it "Matrix advertises 'consume' for video_visit" do
    expect(Pito::Dispatch::Matrix.actions_for("video_visit")).to include("consume")
  end

  describe "consume" do
    subject(:result) do
      handler.call(event: event_for(video.id), rest: "consume", conversation:)
    end

    it "returns a Mutation to the system_follow_up surface kind" do
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.kind).to eq(:system_follow_up)
    end

    it "rebuilds the :visited payload (visit_state visited, no shimmer)" do
      expect(result.payload["visit_state"]).to eq("visited")
      expect(result.payload["body"]).not_to include("pito-network-shimmer")
    end

    it "is not follow-up-able once consumed (graceful repeat no-op)" do
      expect(Pito::FollowUp.followupable?(result.payload)).to be false
    end

    it "defaults to the :youtube destination when visit_destination is absent" do
      expect(result.payload["body"]).to include("www.youtube.com/watch?v=yt_abc")
      expect(result.payload["body"]).not_to include("studio.youtube.com")
    end
  end

  describe "consume preserves the visit_destination from the source event" do
    it "rebuilds the :visited URL as studio when the source was stamped studio" do
      result = handler.call(
        event:        event_for(video.id, "visit_destination" => "studio"),
        rest:         "consume",
        conversation:
      )
      expect(result.payload["body"]).to include("studio.youtube.com/video/yt_abc/edit")
      expect(result.payload["body"]).not_to include("www.youtube.com/watch?v=yt_abc")
    end

    it "rebuilds the :visited URL as youtube when the source was stamped youtube" do
      result = handler.call(
        event:        event_for(video.id, "visit_destination" => "youtube"),
        rest:         "consume",
        conversation:
      )
      expect(result.payload["body"]).to include("www.youtube.com/watch?v=yt_abc")
    end
  end

  describe "errors" do
    it "returns an Error for an unknown action" do
      result = handler.call(event: event_for(video.id), rest: "nope", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "returns an Error when the video is gone" do
      result = handler.call(event: event_for(0), rest: "consume", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
