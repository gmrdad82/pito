# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::ImportDone do
  let(:conversation) { create(:conversation) }
  let(:game)         { create(:game, title: "Rayman") }

  subject(:payload) { described_class.call(game, conversation: conversation) }

  let(:body) { payload["body"] }

  # ── clickable #id → "show game #id" + Enter (19.3) ───────────────────────────
  it "renders the #id as a CLICKABLE action-shimmer token" do
    expect(body).to include("pito-action-shimmer")
    expect(body).to include(">##{game.id}<")
  end

  it "wires the click to prefill 'show game #id' and submit (Enter)" do
    expect(body).to include('data-controller="pito--chat-prefill"')
    expect(body).to include("data-pito--chat-prefill-text-value=\"show game ##{game.id}\"")
    expect(body).to include('data-pito--chat-prefill-submit-value="true"')
  end

  # ── inline timestamp (19.3) ──────────────────────────────────────────────────
  it "puts the timestamp inline via the ts-slot (same row as the copy)" do
    expect(body).to include("data-pito-ts-slot")
  end

  # ── see_it line removed (19.3) ───────────────────────────────────────────────
  it "no longer renders the 'Type show game to see it in full' line" do
    expect(body).not_to include("see it in full")
  end

  it "keeps the 'A new adventure awaits.' line" do
    expect(body).to include("A new adventure awaits.")
  end

  it "shimmers the title as the subject" do
    expect(body).to include("pito-subject-shimmer")
  end

  # ── still followupable (unchanged) ───────────────────────────────────────────
  it "stamps reply_target 'game_imported' + a reply_handle" do
    expect(payload["reply_target"]).to eq("game_imported")
    expect(payload["reply_handle"]).to be_present
  end
end
