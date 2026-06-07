# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

# Full end-to-end: /disconnect → stamped confirmation → #handle confirm|cancel
# Verifies the follow-up engine path: echo + appended confirmation_follow_up +
# original consumed.
RSpec.describe "Confirmation via follow-up engine", type: :request do
  include ActionCable::TestHelper

  let(:conversation)  { Conversation.singleton }
  let(:connection)    { create(:youtube_connection) }
  let!(:channel)      { create(:channel, handle: "@pito", youtube_connection: connection) }
  let!(:video)        { create(:video, channel:) }

  before do
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed:)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
    conversation.turns.destroy_all

    # Ensure handler is loaded + registered.
    Pito::FollowUp::Handlers::Confirmation
    Pito::FollowUp::Registry.register(Pito::FollowUp::Handlers::Confirmation)
  end

  def confirmation_event
    conversation.events.where(kind: "confirmation").last
  end

  context "confirm (destroy)" do
    before do
      # Emit the confirmation event by running /disconnect.
      perform_enqueued_jobs do
        post "/chat", params: { input: "/disconnect @pito", uuid: conversation.uuid }
      end
    end

    it "creates a confirmation event stamped with reply_handle + reply_target" do
      evt = confirmation_event
      expect(evt).not_to be_nil
      expect(evt.payload["reply_handle"]).to match(/\A[a-z]+-\d{4}\z/)
      expect(evt.payload["reply_target"]).to eq("confirmation")
    end

    it "#<handle> confirm echoes + appends confirmation_follow_up + consumes original" do
      handle = confirmation_event.payload["reply_handle"]

      perform_enqueued_jobs do
        post "/chat", params: { input: "##{handle} confirm", uuid: conversation.uuid }
      end

      # Echo exists
      echo = conversation.events.find_by(kind: "echo")
      expect(echo).not_to be_nil

      # Appended outcome event
      outcome = conversation.events.find_by(kind: "confirmation_follow_up")
      expect(outcome).not_to be_nil
      expect(outcome.payload["resolved"]).to be(true)
      expect(outcome.payload["outcome"]).to eq("confirm")
      expect(outcome.payload["outcome_text"]).to include("@pito")

      # Channel destroyed
      expect(Channel.find_by(id: channel.id)).to be_nil

      # Original confirmation consumed
      expect(confirmation_event.reload.payload["reply_consumed"]).to be(true)
    end
  end

  context "cancel (keep channel)" do
    before do
      perform_enqueued_jobs do
        post "/chat", params: { input: "/disconnect @pito", uuid: conversation.uuid }
      end
    end

    it "#<handle> cancel appends outcome + consumes + channel survives" do
      handle = confirmation_event.payload["reply_handle"]

      perform_enqueued_jobs do
        post "/chat", params: { input: "##{handle} cancel", uuid: conversation.uuid }
      end

      # Outcome event appended
      outcome = conversation.events.find_by(kind: "confirmation_follow_up")
      expect(outcome).not_to be_nil
      expect(outcome.payload["outcome"]).to eq("cancel")

      # Channel survives
      expect(Channel.find_by(id: channel.id)).to be_present

      # Original consumed
      expect(confirmation_event.reload.payload["reply_consumed"]).to be(true)
    end
  end
end
