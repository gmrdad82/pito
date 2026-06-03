# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConfirmationDispatchJob, type: :job do
  let(:conversation) { Conversation.create! }
  let(:connection)   { create(:youtube_connection) }
  let!(:channel)     { create(:channel, handle: "@pito", youtube_connection: connection) }
  let!(:video1)      { create(:video, channel:) }
  let!(:video2)      { create(:video, channel:) }

  let(:turn) do
    conversation.turns.create!(
      input_kind: :slash, input_text: "/disconnect @pito", position: 1
    )
  end
  let!(:confirmation_event) do
    Event.create_with_position!(
      conversation:, turn:, kind: "confirmation",
      payload: {
        command:             "disconnect",
        body:                "Disconnect from @pito?",
        confirmation_handle: "beta-2222",
        channel_id:          channel.id,
        authenticated:       true
      }
    )
  end

  describe "confirm — disconnect" do
    it "destroys the channel" do
      expect {
        described_class.perform_now(confirmation_event.id, action: "confirm")
      }.to change(Channel, :count).by(-1)
    end

    it "destroys all videos via cascade" do
      expect {
        described_class.perform_now(confirmation_event.id, action: "confirm")
      }.to change(Video, :count).by(-2)
    end

    it "destroys the YoutubeConnection when it was the last channel" do
      expect {
        described_class.perform_now(confirmation_event.id, action: "confirm")
      }.to change(YoutubeConnection, :count).by(-1)
    end

    it "keeps the YoutubeConnection when other channels remain" do
      create(:channel, youtube_connection: connection)
      expect {
        described_class.perform_now(confirmation_event.id, action: "confirm")
      }.not_to change(YoutubeConnection, :count)
    end

    it "marks the event resolved: confirmed and flips kind to confirmation_follow_up" do
      described_class.perform_now(confirmation_event.id, action: "confirm")
      confirmation_event.reload
      expect(confirmation_event.kind).to eq("confirmation_follow_up")
      expect(confirmation_event.payload["resolved"]).to be(true)
      expect(confirmation_event.payload["outcome"]).to eq("confirm")
    end

    it "includes outcome_text mentioning the channel and video count" do
      described_class.perform_now(confirmation_event.id, action: "confirm")
      text = confirmation_event.reload.payload["outcome_text"]
      expect(text).to include("@pito")
      expect(text).to include("2")
    end
  end

  describe "cancel — disconnect" do
    it "does not destroy the channel" do
      expect {
        described_class.perform_now(confirmation_event.id, action: "cancel")
      }.not_to change(Channel, :count)
    end

    it "marks the event resolved: cancelled and flips kind to confirmation_follow_up" do
      described_class.perform_now(confirmation_event.id, action: "cancel")
      confirmation_event.reload
      expect(confirmation_event.kind).to eq("confirmation_follow_up")
      expect(confirmation_event.payload["resolved"]).to be(true)
      expect(confirmation_event.payload["outcome"]).to eq("cancel")
    end

    it "includes outcome_text mentioning the channel handle" do
      described_class.perform_now(confirmation_event.id, action: "cancel")
      text = confirmation_event.reload.payload["outcome_text"]
      expect(text).to include("@pito")
    end
  end

  describe "channel already gone (confirm after manual delete)" do
    before { channel.destroy! }

    it "does not raise" do
      expect {
        described_class.perform_now(confirmation_event.id, action: "confirm")
      }.not_to raise_error
    end

    it "marks the event resolved with an already_gone message" do
      described_class.perform_now(confirmation_event.id, action: "confirm")
      text = confirmation_event.reload.payload["outcome_text"]
      expect(text).to be_present
    end
  end
end
