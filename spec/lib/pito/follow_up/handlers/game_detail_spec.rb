# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameDetail, type: :service do
  subject(:handler) { described_class.new }

  let(:conversation) { create(:conversation) }
  let!(:game) { create(:game, title: "Lies of P") }
  let(:turn)  do
    conversation.turns.create!(
      input_kind: :hashtag, input_text: "#test-1234 rm", position: 1
    )
  end

  # Build a stub detail-event with game_id stamped (as DetailMessage now does).
  def build_detail_event(payload_overrides = {})
    base_payload = {
      "body"         => "<div>card html</div>",
      "html"         => true,
      "game_id"      => game.id,
      "reply_handle" => "detail-1234",
      "reply_target" => "game_detail"
    }.merge(payload_overrides)
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload: base_payload
    )
  end

  it "registers for the game_detail target" do
    expect(described_class.target).to eq("game_detail")
  end

  it "Matrix serves :append mode for game_detail" do
    expect(Pito::Dispatch::Matrix.mode_for("game_detail")).to eq(:append)
  end

  # ── rm / delete ─────────────────────────────────────────────────────────────

  describe "#call — rm" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "rm", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a confirmation event" do
      expect(result.events.first[:kind].to_s).to eq("confirmation")
    end

    it "uses the game_delete command" do
      expect(result.events.first[:payload]["command"]).to eq("game_delete")
    end

    it "carries game_id and game_title" do
      payload = result.events.first[:payload]
      expect(payload["game_id"]).to eq(game.id)
      expect(payload["game_title"]).to eq("Lies of P")
    end

    it "stamps the confirmation as followupable (confirmation target)" do
      payload = result.events.first[:payload]
      expect(payload["reply_target"]).to eq("confirmation")
    end
  end

  describe "#call — delete (alias for rm)" do
    let(:source_event) { build_detail_event }

    it "also emits a game_delete confirmation" do
      result = handler.call(event: source_event, rest: "delete", conversation:)
      expect(result.events.first[:payload]["command"]).to eq("game_delete")
    end
  end

  describe "#call — rm when game is missing/deleted" do
    let(:source_event) { build_detail_event("game_id" => 0) }

    it "returns a Result::Append with a not-found message (delegated path)" do
      result = handler.call(event: source_event, rest: "rm", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "does not raise" do
      expect { handler.call(event: source_event, rest: "rm", conversation:) }.not_to raise_error
    end
  end

  # ── reindex ──────────────────────────────────────────────────────────────────

  describe "#call — reindex" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "reindex", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a confirmation with command game_reindex (Voyage re-embed)" do
      expect(result.events.first[:payload]["command"]).to eq("game_reindex")
    end

    it "carries game_id and game_title" do
      payload = result.events.first[:payload]
      expect(payload["game_id"]).to eq(game.id)
      expect(payload["game_title"]).to eq("Lies of P")
    end
  end

  describe "#call — reindex when game is missing/deleted" do
    let(:source_event) { build_detail_event("game_id" => 0) }

    it "returns a Result::Append with a not-found message (delegated path)" do
      result = handler.call(event: source_event, rest: "reindex", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "does not raise" do
      expect { handler.call(event: source_event, rest: "reindex", conversation:) }.not_to raise_error
    end
  end

  # ── actions list ─────────────────────────────────────────────────────────────

  it "Matrix advertises rm, del, delete, reindex, link, unlink, platform, price, shinies, sync, analyze for game_detail" do
    expect(Pito::Dispatch::Matrix.actions_for("game_detail")).to include(
      "rm", "del", "delete", "reindex", "link", "unlink", "platform", "price", "shinies", "sync", "analyze"
    )
  end

  # ── link to video (delegated to Chat::Handlers::Link) ───────────────────────

  describe "#call — link to video" do
    let(:source_event)  { build_detail_event }
    let(:connection)    { create(:youtube_connection) }
    let(:channel)       { create(:channel, youtube_connection: connection) }
    let!(:video)        { create(:video, channel: channel, title: "Let's Play Lies of P") }

    context "with a valid video id" do
      subject(:result) do
        handler.call(event: source_event, rest: "link to video ##{video.id}", conversation:)
      end

      it "returns a Result::Append" do
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "creates a VideoGameLink" do
        expect { result }.to change(VideoGameLink, :count).by(1)
      end

      it "is idempotent (no duplicate link on repeat)" do
        handler.call(event: source_event, rest: "link to video ##{video.id}", conversation:)
        expect { handler.call(event: source_event, rest: "link to video ##{video.id}", conversation:) }
          .not_to change(VideoGameLink, :count)
      end

      it "appends a witty ack text" do
        text = result.events.first[:payload]["text"]
        expect(text).to be_present
      end
    end

    context "with a video title reference (now id-only)" do
      it "returns a usage hint and does not link (titles no longer resolve)" do
        result = handler.call(event: source_event, rest: "link to video let's play lies of p", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(VideoGameLink.where(video:, game:).exists?).to be false
      end
    end

    context "with an unknown video" do
      it "returns a not-found append with witty text" do
        result = handler.call(event: source_event, rest: "link to video 99999", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Append)
        text = result.events.first[:payload]["text"]
        expect(text).to be_present
      end
    end

    context "with missing video ref" do
      it "returns a Result::Error (usage hint from Link handler)" do
        result = handler.call(event: source_event, rest: "link to video", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
      end
    end
  end

  # ── unlink from video (delegated to Chat::Handlers::Unlink) ─────────────────

  describe "#call — unlink from video" do
    let(:source_event)  { build_detail_event }
    let(:connection)    { create(:youtube_connection) }
    let(:channel)       { create(:channel, youtube_connection: connection) }
    let!(:video)        { create(:video, channel: channel, title: "Let's Play Lies of P") }
    let!(:vgl)          { create(:video_game_link, video: video, game: game) }

    it "returns a Result::Append" do
      result = handler.call(event: source_event, rest: "unlink from video ##{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "destroys the VideoGameLink" do
      expect {
        handler.call(event: source_event, rest: "unlink from video ##{video.id}", conversation:)
      }.to change(VideoGameLink, :count).by(-1)
    end

    it "appends a witty unlinked ack text" do
      result = handler.call(event: source_event, rest: "unlink from video ##{video.id}", conversation:)
      text = result.events.first[:payload]["text"]
      expect(text).to be_present
    end
  end

  # ── multi-target link to videos ──────────────────────────────────────────────

  describe "#call — multi-target link to videos" do
    let(:source_event) { build_detail_event }
    let(:connection)   { create(:youtube_connection) }
    let(:channel)      { create(:channel, youtube_connection: connection) }
    let!(:video1)      { create(:video, channel: channel, title: "Lies of P Part 1") }
    let!(:video2)      { create(:video, channel: channel, title: "Lies of P Part 2") }

    subject(:result) do
      handler.call(event: source_event, rest: "link to ##{video1.id},##{video2.id}", conversation:)
    end

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "creates VideoGameLinks for both target videos" do
      expect { result }.to change(VideoGameLink, :count).by(2)
    end

    it "uses the card's game as source (not parsed from rest)" do
      result
      expect(VideoGameLink.where(game: game, video: video1)).to exist
      expect(VideoGameLink.where(game: game, video: video2)).to exist
    end

    it "does NOT consume the card (consume: false — card stays reusable)" do
      expect(result.consume).to be false
    end

    it "is repeatable — calling again does not raise or duplicate links" do
      handler.call(event: source_event, rest: "link to ##{video1.id},##{video2.id}", conversation:)
      expect {
        handler.call(event: source_event, rest: "link to ##{video1.id},##{video2.id}", conversation:)
      }.not_to change(VideoGameLink, :count)
    end
  end

  # ── multi-target unlink from videos ──────────────────────────────────────────

  describe "#call — multi-target unlink from videos" do
    let(:source_event) { build_detail_event }
    let(:connection)   { create(:youtube_connection) }
    let(:channel)      { create(:channel, youtube_connection: connection) }
    let!(:video1)      { create(:video, channel: channel, title: "Lies of P Part 1") }
    let!(:video2)      { create(:video, channel: channel, title: "Lies of P Part 2") }
    let!(:vgl1)        { create(:video_game_link, video: video1, game: game) }
    let!(:vgl2)        { create(:video_game_link, video: video2, game: game) }

    subject(:result) do
      handler.call(event: source_event, rest: "unlink from ##{video1.id},##{video2.id}", conversation:)
    end

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "destroys links for both target videos" do
      expect { result }.to change(VideoGameLink, :count).by(-2)
    end

    it "does NOT consume the card (consume: false — card stays reusable)" do
      expect(result.consume).to be false
    end

    it "is repeatable — calling unlink twice does not raise" do
      result # first call destroys both
      expect {
        handler.call(event: source_event, rest: "unlink from ##{video1.id},##{video2.id}", conversation:)
      }.not_to raise_error
    end
  end

  # ── unknown action ───────────────────────────────────────────────────────────

  describe "#call — price [set] <amount> | price unset" do
    let(:source_event) { build_detail_event }

    it "sets the segment game's price from the `price set <amount>` form" do
      result = handler.call(event: source_event, rest: "price set 59.99", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:kind]).to eq(:system)
      expect(game.reload.price).to eq(BigDecimal("59.99"))
    end

    it "sets the price from the bare `price <amount>` form" do
      handler.call(event: source_event, rest: "price 20", conversation:)
      expect(game.reload.price).to eq(BigDecimal("20.00"))
    end

    it "clears the price on `price unset`" do
      game.update!(price: BigDecimal("40.00"))
      result = handler.call(event: source_event, rest: "price unset", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(game.reload.price).to be_nil
    end

    it "emits the price confirmation with the formatted euro amount" do
      result = handler.call(event: source_event, rest: "price set 59.99", conversation:)
      expect(result.events.first[:payload]["text"]).to include("Lies of P").and include("€59.99")
    end

    it "sets an explicit 0 as free and confirms it as €0.00" do
      result = handler.call(event: source_event, rest: "price set 0", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(game.reload.price).to eq(0)
      expect(result.events.first[:payload]["text"]).to include("Lies of P").and include("€0.00")
    end

    it "errors with missing_price when no amount is given" do
      result = handler.call(event: source_event, rest: "price set", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_detail.errors.missing_price")
    end

    it "errors when the segment's game no longer exists" do
      event = build_detail_event("game_id" => game.id)
      game.destroy
      result = handler.call(event: event, rest: "price set 9.99", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_detail.errors.game_not_found")
    end
  end

  # ── shinies (delegated to Chat::Handlers::Shinies via ToolDelegator) ───────────

  describe "#call — shinies" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "shinies", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends the shinies message for the game" do
      payload = result.events.first[:payload]
      expect(payload["body"]).to include("pito-achievement-shinies")
      expect(payload["game_id"]).to eq(game.id)
    end

    it "does NOT return an invalid_action error (shinies is now a declared action)" do
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end
  end

  describe "#call — unknown action" do
    let(:source_event) { build_detail_event }

    it "returns a Result::Error" do
      result = handler.call(event: source_event, rest: "frobnicate", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_detail.errors.invalid_action")
    end
  end

  # ── regression guard: config↔handler contract ────────────────────────────────
  # channels / similar / vids / at-a-glance were declared in tools.yml for
  # game_detail but shadowed by a hardcoded gate here. Every config-declared reply
  # verb (bar the follow-up-only specials) must reach the matrix-gated ToolDelegator.
  describe "every config-declared reply verb reaches ToolDelegator" do
    let(:source_event) { build_detail_event }
    let(:sentinel)     { Pito::FollowUp::Result::Append.new(events: []) }
    before { allow(Pito::FollowUp::ToolDelegator).to receive(:call).and_return(sentinel) }

    specials  = %w[analyze price] # follow-up-only, handled in-card
    delegated = Pito::FollowUp::Registry.actions_for("game_detail") - specials

    delegated.each do |verb|
      it "delegates '#{verb}' instead of rejecting it" do
        expect(handler.call(event: source_event, rest: verb, conversation:)).to eq(sentinel)
      end
    end
  end

  # ── registry ─────────────────────────────────────────────────────────────────

  describe "registry" do
    before { Pito::FollowUp::Registry.register(described_class) }

    it "is registered under 'game_detail'" do
      expect(Pito::FollowUp::Registry.for("game_detail")).to eq(described_class)
    end

    it "has mode :append" do
      expect(Pito::FollowUp::Registry.mode_for("game_detail")).to eq(:append)
    end
  end
end
