# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: resume_missing hashtag follow-up (recognition/gating) ────
#
# Verifies:
#   1. Registry.actions_for("resume_missing") declares "new" and "create".
#   2. Both valid actions route through the handler and return Result::Append.
#   3. Unknown actions return Result::Error (invalid_action).
#
# Real Conversation rows are allowed (for Conversation.create! inside the
# handler). ActionCable broadcasts from Conversation::Rename are stubbed.
RSpec.describe "Dispatch matrix — resume_missing hashtag follow-up (recognition)", type: :dispatch do
  subject(:handler) { Pito::FollowUp::Handlers::ResumeMissing.new }

  let(:conversation) { Conversation.create! }

  let(:source_event) do
    instance_double(Event, payload: {
      "resume_name"  => "My Game",
      "reply_target" => "resume_missing"
    })
  end

  def call(rest)
    handler.call(event: source_event, rest: rest, conversation: conversation)
  end

  before do
    Pito::FollowUp::Registry.register_all!

    broadcaster = instance_double(Pito::Stream::Broadcaster, broadcast_conversation_name: nil)
    allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
    allow(Pito::Stream::Broadcaster).to receive(:broadcast_global_conversation_row)
  end

  # ── Registry declarations ─────────────────────────────────────────────────

  describe "Pito::FollowUp::Registry" do
    it "for('resume_missing') is Handlers::ResumeMissing" do
      expect(Pito::FollowUp::Registry.for("resume_missing"))
        .to eq(Pito::FollowUp::Handlers::ResumeMissing)
    end

    it "mode_for('resume_missing') is :append" do
      expect(Pito::FollowUp::Registry.mode_for("resume_missing")).to eq(:append)
    end

    it "actions_for('resume_missing') includes 'new'" do
      expect(Pito::FollowUp::Registry.actions_for("resume_missing").map(&:to_s)).to include("new")
    end

    it "actions_for('resume_missing') includes 'create'" do
      expect(Pito::FollowUp::Registry.actions_for("resume_missing").map(&:to_s)).to include("create")
    end
  end

  # ── Valid actions → Result::Append ───────────────────────────────────────

  describe "valid actions → Result::Append" do
    %w[new create].each do |action|
      it "#{action.inspect} → Result::Append" do
        expect(call(action)).to be_a(Pito::FollowUp::Result::Append)
      end
    end
  end

  # ── Unknown actions → Result::Error ─────────────────────────────────────

  describe "unknown actions → Result::Error (invalid_action)" do
    %w[bogus list show open resume cancel delete].each do |bad|
      it "#{bad.inspect} → Result::Error" do
        expect(call(bad)).to be_a(Pito::FollowUp::Result::Error)
      end

      it "#{bad.inspect} → error key references invalid_action" do
        expect(call(bad).message_key).to include("invalid_action")
      end
    end
  end
end
