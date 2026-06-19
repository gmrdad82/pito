# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe GameImportJob, type: :job do
  include ActionCable::TestHelper

  # ── Shared setup ─────────────────────────────────────────────────────────────

  let(:conversation)    { Conversation.create! }
  let(:igdb_id)         { 1020 }
  let(:title)           { "Lies of P" }
  let(:game)            { create(:game, igdb_id: igdb_id, title: title) }

  # Stub SyncGame so we don't hit the IGDB API
  let(:sync_game_double) { instance_double(Game::Igdb::SyncGame, call: game) }

  # Track sidebar broadcast_import_step calls
  let(:sidebar_steps) { [] }

  before do
    # Stub SyncGame
    allow(Game::Igdb::SyncGame).to receive(:new).and_return(sync_game_double)
    allow(sync_game_double).to receive(:call) { game.update_column(:igdb_synced_at, Time.current); game }

    # Stub Importer (covers both import + resync paths)
    allow(Game::Igdb::Importer).to receive(:call).with(igdb_id: igdb_id, title: title)
                                                 .and_return({ game: game, action: :import })

    # Stub VoyageIndexer (skips actual Voyage HTTP call)
    allow(::Game::VoyageIndexer).to receive(:call)

    # Stub ScoreCalculator
    allow(Pito::Game::ScoreCalculator).to receive(:call).and_return(80.0)

    # Stub DetailMessage
    allow(Pito::MessageBuilder::Game::Detail).to receive(:call)
      .and_return({ "body" => "<div>detail</div>", "html" => true })

    # Stub update_column for all column names (resyncing, score, igdb_synced_at, etc.)
    allow(game).to receive(:update_column).with(anything, anything)
    allow(game).to receive(:reload).and_return(game)
    allow(Game).to receive(:where).and_call_original
    allow(Game).to receive(:where).with(id: game.id).and_return(
      double(update_all: nil)
    )

    # Stub broadcast_import_step to capture sidebar step calls and avoid
    # actual ActionCable broadcast (steps go to sidebar, not chat).
    allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:broadcast_import_step) do |_broadcaster, step:, label:, done:|
      sidebar_steps << { step: step, label: label, done: done }
    end
  end

  def perform
    described_class.new.perform(
      igdb_id:         igdb_id,
      title:           title,
      conversation_id: conversation.id
    )
  end

  # ── No-op guard ──────────────────────────────────────────────────────────────

  it "is a no-op when the conversation does not exist" do
    expect { described_class.new.perform(igdb_id:, title:, conversation_id: 0) }
      .not_to raise_error
  end

  # ── step broadcasts go to SIDEBAR (broadcast_import_step), NOT chat ──────────

  it "calls broadcast_import_step 9 times (pending+done for 1/3/4/5; done-only for 2)" do
    perform
    expect(sidebar_steps.length).to eq(9)
  end

  it "broadcasts pending then done for steps 1,3,4,5; done-only for step 2" do
    perform
    [ 1, 3, 4, 5 ].each do |step|
      pending_calls = sidebar_steps.select { |s| s[:step] == step && s[:done] == false }
      done_calls    = sidebar_steps.select { |s| s[:step] == step && s[:done] == true }
      expect(pending_calls.count).to eq(1), "expected 1 pending for step #{step}"
      expect(done_calls.count).to eq(1),    "expected 1 done for step #{step}"
    end
    # Step 2 (cover, already fetched in step 1) is done-only — no pending, which
    # raced over the cable and left the shimmer stuck.
    expect(sidebar_steps.select { |s| s[:step] == 2 && s[:done] == false }).to be_empty
    expect(sidebar_steps.select { |s| s[:step] == 2 && s[:done] == true }.count).to eq(1)
  end

  it "does NOT create step events in the conversation (steps stay in sidebar)" do
    perform
    step_events = conversation.events.where("payload->>'import_step' IS NOT NULL")
    expect(step_events.count).to eq(0)
  end

  # ── exactly 2 messages go to the main chat ───────────────────────────────────

  it "streams a detail message event (html: true, after step 3)" do
    perform
    detail = conversation.events.find { |e| e.payload["html"] == true && e.payload["body"]&.include?("detail") }
    expect(detail).to be_present
  end

  it "streams an enhanced message event (kind: enhanced) that is NOT follow-up-able" do
    perform
    enhanced = conversation.events.find { |e|
      e.payload["body"].to_s.include?("pito-game-enhanced-message")
    }
    expect(enhanced).to be_present
    # Renders via the Enhanced chrome (pito-blue border), not a System message.
    expect(enhanced.kind).to eq("enhanced")
    # The enhanced message carries no #handle — only the standard detail does.
    expect(enhanced.payload["reply_handle"]).to be_blank
    expect(enhanced.payload["reply_target"]).to be_blank
  end

  it "stamps game_id in the enhanced message payload" do
    perform
    enhanced = conversation.events.find { |e| e.payload["body"].to_s.include?("pito-game-enhanced-message") }
    expect(enhanced.payload["game_id"]).to be_present
  end

  it "calls Game::Igdb::Importer with the correct igdb_id and title" do
    expect(Game::Igdb::Importer).to receive(:call).with(igdb_id: igdb_id, title: title)
    perform
  end

  it "calls Game::Igdb::SyncGame#call" do
    expect(sync_game_double).to receive(:call)
    perform
  end

  it "calls Game::VoyageIndexer for step 4" do
    expect(::Game::VoyageIndexer).to receive(:call)
    perform
  end

  it "completes the turn (sets completed_at)" do
    perform
    turn = conversation.turns.last
    expect(turn.completed_at).to be_present
  end

  # ── emit_error branch (SyncGame raises ValidationError) ──────────────────────

  context "when Game::Igdb::SyncGame raises a ValidationError" do
    before do
      allow(sync_game_double).to receive(:call)
        .and_raise(Game::Igdb::Client::ValidationError, "IGDB rejected the payload")
    end

    it "emits an error event into the conversation" do
      perform
      error_events = conversation.events.select { |e| e.kind == "error" }
      expect(error_events).not_to be_empty
    end

    it "does NOT stream the detail or enhanced messages" do
      perform
      detail   = conversation.events.find { |e| e.payload["reply_target"] == "game_detail" }
      enhanced = conversation.events.find { |e| e.payload["body"].to_s.include?("pito-game-enhanced-message") }
      expect(detail).to be_nil
      expect(enhanced).to be_nil
    end

    it "completes the turn even on error" do
      perform
      turn = conversation.turns.last
      expect(turn.completed_at).to be_present
    end
  end

  # ── Resync path (already-in-library) ─────────────────────────────────────────

  context "when game already exists in library (resync)" do
    before do
      allow(Game::Igdb::Importer).to receive(:call).with(igdb_id: igdb_id, title: title)
                                                   .and_return({ game: game, action: :resync })
    end

    it "still broadcasts all 5 steps to the sidebar" do
      perform
      expect(sidebar_steps.map { |s| s[:step] }.uniq.sort).to eq([ 1, 2, 3, 4, 5 ])
    end

    it "still streams both chat messages" do
      perform
      detail   = conversation.events.find { |e| e.payload["html"] == true && e.payload["body"]&.include?("detail") }
      enhanced = conversation.events.find { |e| e.payload["body"].to_s.include?("pito-game-enhanced-message") }
      expect(detail).to be_present
      expect(enhanced).to be_present
    end
  end

  # ── BUG A: VoyageEmbeddingNil propagates (not swallowed) ─────────────────────

  context "when Game::VoyageIndexer raises VoyageEmbeddingNil" do
    before do
      allow(::Game::VoyageIndexer).to receive(:call)
        .and_raise(Pito::Error::VoyageEmbeddingNil.new(resource_type: "game", resource_id: game.id))
    end

    it "raises VoyageEmbeddingNil (not swallowed) so retry_on can handle it" do
      expect { perform }.to raise_error(Pito::Error::VoyageEmbeddingNil)
    end

    it "does NOT raise StandardError (the generic rescue does not eat embedding failures)" do
      # retry_on only intercepts VoyageEmbeddingNil; it must not be re-wrapped
      begin
        perform
      rescue Pito::Error::VoyageEmbeddingNil
        # expected
      rescue StandardError => e
        raise "Unexpected StandardError raised instead of VoyageEmbeddingNil: #{e.class}: #{e.message}"
      end
    end
  end

  # ── BUG A: idempotency — calling perform twice does not duplicate events ──────

  context "idempotency on retry (perform called twice simulating a re-enqueue)" do
    it "reuses the same open turn on the second call" do
      perform
      # The first call leaves the turn open (completed) but let us simulate
      # a retry by re-opening it: set completed_at = nil on the existing turn.
      turn = conversation.turns.last
      turn.update_column(:completed_at, nil)

      perform

      # Still only one turn with this input_text.
      expect(conversation.turns.where(input_text: "/games import #{title}").count).to eq(1)
    end

    it "does not duplicate echo events on retry" do
      perform
      turn = conversation.turns.last
      turn.update_column(:completed_at, nil)

      perform

      expect(conversation.events.where(kind: "echo").count).to eq(1)
    end

    it "does not duplicate detail (system) events on retry" do
      perform
      turn = conversation.turns.last
      turn.update_column(:completed_at, nil)

      perform

      expect(conversation.events.where(kind: "system").count).to eq(1)
    end

    it "does not duplicate enhanced events on retry" do
      perform
      turn = conversation.turns.last
      turn.update_column(:completed_at, nil)

      perform

      expect(conversation.events.where(kind: "enhanced").count).to eq(1)
    end

    it "completes the turn after the successful retry" do
      perform
      turn = conversation.turns.last
      turn.update_column(:completed_at, nil)

      perform

      expect(turn.reload.completed_at).to be_present
    end
  end
end
