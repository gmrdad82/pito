# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelDistributionFillJob do
  let(:conversation) { Conversation.create! }
  let(:turn) { create(:turn, conversation: conversation) }
  let(:game) { create(:game) }
  let(:broadcaster) do
    instance_double(
      Pito::Stream::Broadcaster,
      replace_event: nil, resolve_thinking_for: nil,
      complete_turn: nil, all_thinking_resolved?: true
    )
  end

  before do
    allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
    # Don't hit YouTube for watch-time in job specs; the distribution falls back to
    # videos + views. A dedicated example below asserts the fetch is invoked.
    allow(Game::ChannelWatchTime).to receive(:hours_for).and_return({})
  end

  def pending_event
    payload = Pito::MessageBuilder::Game::Channels.pending(game, conversation: conversation)
    create(:event, conversation: conversation, turn: turn, kind: :enhanced, payload: payload)
  end

  # A channel that covers the game (1 linked video with views).
  def covering_channel(views: 100)
    ch = create(:channel)
    v  = create(:video, channel: ch)
    create(:video_game_link, video: v, game: game)
    Pito::Stats.set(v, :views, views)
    ch
  end

  it "flips the marker to ready and persists a body" do
    ev = pending_event
    described_class.perform_now(turn.id)
    ev.reload
    expect(ev.payload.dig("channel_distribution", "status")).to eq("ready")
    expect(ev.payload["body"]).to be_present
  end

  it "broadcasts the swap and resolves the message indicator" do
    pending_event
    described_class.perform_now(turn.id)
    expect(broadcaster).to have_received(:replace_event)
    expect(broadcaster).to have_received(:resolve_thinking_for)
  end

  it "fills the distribution bars when a channel covers the game" do
    covering_channel(views: 1_000)
    ev = pending_event
    described_class.perform_now(turn.id)
    expect(ev.reload.payload["body"]).to include("pito-metric--bar")
  end

  it "leaves the NoData canvas when channels exist but none cover the game" do
    create(:channel) # exists (so the recommendation column renders) but no linked video
    ev = pending_event
    described_class.perform_now(turn.id)
    body = ev.reload.payload["body"]
    expect(body).to include("pito-metric--nodata")
    expect(body).not_to include("pito-metric--bar")
  end

  it "completes the turn when all indicators are resolved" do
    pending_event
    described_class.perform_now(turn.id)
    expect(broadcaster).to have_received(:complete_turn)
  end

  it "invokes the dedicated lifetime watch-time fetch for the covering videos" do
    covering_channel(views: 100)
    pending_event
    described_class.perform_now(turn.id)
    expect(Game::ChannelWatchTime).to have_received(:hours_for)
  end
end
