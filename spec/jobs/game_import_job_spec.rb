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
    allow(Pito::Game::DetailMessage).to receive(:call)
      .and_return({ "body" => "<div>detail</div>", "html" => true })

    # Stub update_column for all column names (resyncing, score, igdb_synced_at, etc.)
    allow(game).to receive(:update_column).with(anything, anything)
    allow(game).to receive(:reload).and_return(game)
    allow(Game).to receive(:where).and_call_original
    allow(Game).to receive(:where).with(id: game.id).and_return(
      double(update_all: nil)
    )

    # Stub broadcast_import_step to capture sidebar step calls and avoid
    # actual ActionCable broadcast (T16.8: steps go to sidebar, not chat).
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

  # ── T16.8: step broadcasts go to SIDEBAR (broadcast_import_step), NOT chat ──

  it "calls broadcast_import_step 10 times (pending+done for each of the 5 steps)" do
    perform
    expect(sidebar_steps.length).to eq(10)
  end

  it "broadcasts a pending then done for each step 1–5" do
    perform
    (1..5).each do |step|
      pending_calls = sidebar_steps.select { |s| s[:step] == step && s[:done] == false }
      done_calls    = sidebar_steps.select { |s| s[:step] == step && s[:done] == true }
      expect(pending_calls.count).to eq(1), "expected 1 pending for step #{step}"
      expect(done_calls.count).to eq(1),    "expected 1 done for step #{step}"
    end
  end

  it "does NOT create step events in the conversation (steps stay in sidebar)" do
    perform
    step_events = conversation.events.where("payload->>'import_step' IS NOT NULL")
    expect(step_events.count).to eq(0)
  end

  # ── T16.9: exactly 2 messages go to the main chat ────────────────────────────

  it "streams a detail message event (html: true, after step 3)" do
    perform
    detail = conversation.events.find { |e| e.payload["html"] == true && e.payload["body"]&.include?("detail") }
    expect(detail).to be_present
  end

  it "streams an enhanced message event (html: true, game_enhanced followup)" do
    perform
    enhanced = conversation.events.find { |e|
      e.payload["html"] == true && e.payload["reply_target"] == "game_enhanced"
    }
    expect(enhanced).to be_present
  end

  it "stamps game_id in the enhanced message payload" do
    perform
    enhanced = conversation.events.find { |e| e.payload["reply_target"] == "game_enhanced" }
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
      enhanced = conversation.events.find { |e| e.payload["reply_target"] == "game_enhanced" }
      expect(detail).to be_present
      expect(enhanced).to be_present
    end
  end
end
