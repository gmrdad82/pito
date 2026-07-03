# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::ResumeMissing, type: :service do
  subject(:handler) { described_class.new }

  # Real conversation so the handler can call Conversation.create! against the
  # same DB transaction; the source event uses an instance_double (no factory).
  # let! ensures the conversation is materialized before each count assertion.
  let!(:conversation) { Conversation.create! }

  let(:source_event) do
    instance_double(Event, payload: {
      "resume_name"  => "Awesome",
      "reply_target" => "resume_missing"
    })
  end

  def call(rest)
    handler.call(event: source_event, rest: rest, conversation: conversation)
  end

  # Stub ActionCable broadcasts triggered by Conversation::Rename.call so the
  # specs never hit a missing cable connection.
  before do
    broadcaster = instance_double(Pito::Stream::Broadcaster, broadcast_conversation_name: nil)
    allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
    allow(Pito::Stream::Broadcaster).to receive(:broadcast_global_conversation_row)
  end

  # ── Class declarations ─────────────────────────────────────────────────────

  describe "class declarations" do
    it "target is 'resume_missing'" do
      expect(described_class.target).to eq("resume_missing")
    end

    it "Matrix serves :append mode for resume_missing" do
      expect(Pito::Dispatch::Matrix.mode_for("resume_missing")).to eq(:append)
    end

    it "Matrix advertises 'new' and 'create' for resume_missing" do
      expect(Pito::Dispatch::Matrix.actions_for("resume_missing")).to include("new", "create")
    end
  end

  # ── action: new ───────────────────────────────────────────────────────────

  describe "#call — 'new'" do
    it "returns Result::Append" do
      expect(call("new")).to be_a(Pito::FollowUp::Result::Append)
    end

    it "creates a new Conversation (count +1)" do
      expect { call("new") }.to change(Conversation, :count).by(1)
    end

    it "the new Conversation is titled 'Awesome'" do
      call("new")
      expect(Conversation.order(:created_at).last.title).to eq("Awesome")
    end

    it "appends exactly one event" do
      expect(call("new").events.size).to eq(1)
    end
  end

  # ── action: create ────────────────────────────────────────────────────────

  describe "#call — 'create'" do
    it "returns Result::Append" do
      expect(call("create")).to be_a(Pito::FollowUp::Result::Append)
    end

    it "creates a new Conversation (count +1)" do
      expect { call("create") }.to change(Conversation, :count).by(1)
    end

    it "the new Conversation is titled 'Awesome'" do
      call("create")
      expect(Conversation.order(:created_at).last.title).to eq("Awesome")
    end
  end

  # ── invalid action ────────────────────────────────────────────────────────

  describe "#call — 'bogus' (invalid action)" do
    subject(:result) { call("bogus") }

    it "returns Result::Error" do
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "error message_key references invalid_action" do
      expect(result.message_key).to include("invalid_action")
    end

    it "does NOT create a Conversation" do
      expect { call("bogus") }.not_to change(Conversation, :count)
    end
  end

  # ── blank resume_name ─────────────────────────────────────────────────────

  describe "#call — blank resume_name" do
    let(:source_event) do
      instance_double(Event, payload: {
        "resume_name"  => "   ",
        "reply_target" => "resume_missing"
      })
    end

    it "returns Result::Error even for a valid action word" do
      expect(call("new")).to be_a(Pito::FollowUp::Result::Error)
    end

    it "does NOT create a Conversation" do
      expect { call("new") }.not_to change(Conversation, :count)
    end
  end
end
