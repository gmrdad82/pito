# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::Confirmation, type: :service do
  # Ensure the handler is loaded + registered for these specs.
  before do
    Pito::FollowUp::Registry.register(described_class)
  end

  let(:conversation) { Conversation.create! }
  let(:connection)   { create(:youtube_connection) }
  let!(:channel)     { create(:channel, handle: "@pito", youtube_connection: connection) }
  let!(:video1)      { create(:video, channel:) }
  let!(:video2)      { create(:video, channel:) }

  let(:source_turn) do
    conversation.turns.create!(
      input_kind: :slash, input_text: "/disconnect @pito", position: 1
    )
  end
  let!(:source_event) do
    Event.create_with_position!(
      conversation:, turn: source_turn, kind: "confirmation",
      payload: {
        "command"      => "disconnect",
        "body"         => "Disconnect from @pito?",
        "reply_handle" => "alpha-1111",
        "reply_target" => "confirmation",
        "channel_id"   => channel.id
      }
    )
  end

  def call(rest)
    described_class.new.call(event: source_event, rest:, conversation:)
  end

  # ── action: confirm ───────────────────────────────────────────────────────

  describe "#call — confirm" do
    subject(:result) { call("confirm") }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a single confirmation_follow_up event" do
      expect(result.events.size).to eq(1)
      expect(result.events.first[:kind]).to eq("confirmation_follow_up")
    end

    it "includes outcome: 'confirm'" do
      expect(result.events.first[:payload][:outcome]).to eq("confirm")
    end

    it "includes resolved: true" do
      expect(result.events.first[:payload][:resolved]).to be(true)
    end

    it "includes outcome_text mentioning the handle" do
      expect(result.events.first[:payload][:outcome_text]).to include("@pito")
    end
  end

  # ── action: cancel ────────────────────────────────────────────────────────

  describe "#call — cancel" do
    subject(:result) { call("cancel") }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a confirmation_follow_up event" do
      expect(result.events.first[:kind]).to eq("confirmation_follow_up")
    end

    it "includes outcome: 'cancel'" do
      expect(result.events.first[:payload][:outcome]).to eq("cancel")
    end

    it "does NOT destroy the channel" do
      expect { call("cancel") }.not_to change(Channel, :count)
    end

    it "includes outcome_text mentioning the handle" do
      expect(result.events.first[:payload][:outcome_text]).to include("@pito")
    end
  end

  # ── invalid action ────────────────────────────────────────────────────────

  describe "#call — invalid action" do
    subject(:result) { call("bogus") }

    it "returns a Result::Error" do
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "includes the invalid_action message key" do
      expect(result.message_key).to eq("pito.confirmation.errors.invalid_action")
    end
  end

  # ── executor raises ───────────────────────────────────────────────────────

  describe "#call — executor raises StandardError" do
    before do
      allow(Pito::Confirmation::Executor).to receive(:confirm).and_raise(StandardError, "db error")
    end

    subject(:result) { call("confirm") }

    it "returns a Result::Append (not Error) with execution_failed text" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      text = result.events.first[:payload][:outcome_text]
      expect(text).to include(I18n.t("pito.confirmation.errors.execution_failed"))
    end
  end

  # ── registration ─────────────────────────────────────────────────────────

  describe "registry" do
    it "is registered under 'confirmation'" do
      expect(Pito::FollowUp::Registry.for("confirmation")).to eq(described_class)
    end

    it "has mode :append" do
      expect(Pito::FollowUp::Registry.mode_for("confirmation")).to eq(:append)
    end
  end
end
