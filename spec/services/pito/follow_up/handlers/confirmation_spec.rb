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

  # ── aliases: yes → confirm, no → cancel ──────────────────────────────────────

  describe "#call — action aliases" do
    it "treats 'yes' as confirm" do
      expect(call("yes").events.first[:payload][:outcome]).to eq("confirm")
    end

    it "treats 'ok' as confirm" do
      expect(call("ok").events.first[:payload][:outcome]).to eq("confirm")
    end

    it "treats 'approve' as confirm" do
      expect(call("approve").events.first[:payload][:outcome]).to eq("confirm")
    end

    it "treats 'true' as confirm" do
      expect(call("true").events.first[:payload][:outcome]).to eq("confirm")
    end

    it "treats 'no' as cancel" do
      expect(call("no").events.first[:payload][:outcome]).to eq("cancel")
    end

    it "treats 'false' as cancel" do
      expect(call("false").events.first[:payload][:outcome]).to eq("cancel")
    end

    it "treats 'discard' as cancel" do
      expect(call("discard").events.first[:payload][:outcome]).to eq("cancel")
    end

    it "treats 'y'/'n' as confirm/cancel" do
      expect(call("y").events.first[:payload][:outcome]).to eq("confirm")
      expect(call("n").events.first[:payload][:outcome]).to eq("cancel")
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

  # ── import_videos: system outcome on confirm ──────────────────────────────

  describe "#call — import_videos confirm renders a system outcome" do
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "confirmation",
        payload: {
          "command"         => "import_videos",
          "body"            => "Import new videos from @pito?",
          "reply_handle"    => "alpha-1111",
          "reply_target"    => "confirmation",
          "scope_label"     => "@pito",
          "channel_ids"     => [ channel.id ],
          "conversation_id" => conversation.id
        }
      )
    end

    it "appends a :system event (not the orange confirmation_follow_up) on confirm" do
      expect(call("confirm").events.first[:kind]).to eq("system")
    end

    it "carries the queued progress line as the system text" do
      expect(call("confirm").events.first[:payload]["text"]).to be_present
    end

    it "still renders the orange confirmation_follow_up on cancel" do
      expect(call("cancel").events.first[:kind]).to eq("confirmation_follow_up")
    end
  end

  # ── video_schedule: enhanced outcome on confirm ───────────────────────────

  describe "#call — video_schedule confirm renders an enhanced outcome" do
    let!(:sc_video) { create(:video, channel:, title: "Dungeon Clear", privacy_status: :public, publish_at: nil) }
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "confirmation",
        payload: {
          "command"      => "video_schedule",
          "body"         => "Schedule Dungeon Clear?",
          "reply_handle" => "alpha-1111",
          "reply_target" => "confirmation",
          "video_id"     => sc_video.id,
          "video_title"  => "Dungeon Clear",
          "publish_at"   => 7.days.from_now.utc.iso8601
        }
      )
    end

    before { allow(VideoRemoteStatusSync).to receive(:perform_later) }

    it "appends an :enhanced event (not the orange confirmation_follow_up) on confirm" do
      expect(call("confirm").events.first[:kind]).to eq("enhanced")
    end

    it "carries the scheduled outcome line as the enhanced text" do
      expect(call("confirm").events.first[:payload]["text"]).to be_present
    end

    it "still renders the orange confirmation_follow_up on cancel" do
      expect(call("cancel").events.first[:kind]).to eq("confirmation_follow_up")
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
      expect(text).to include(Pito::Copy.render("pito.copy.confirmation.execution_failed"))
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
