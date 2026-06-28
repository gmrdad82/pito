# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::ChannelDetail, type: :service do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:channel) do
    create(:channel,
           title:              "Alpha Cast",
           handle:             "@alpha",
           youtube_channel_id: "UCabc")
  end
  let(:turn) do
    conversation.turns.create!(
      input_kind: :hashtag, input_text: "#detail-1234 visit channel", position: 1
    )
  end

  def build_detail_event(payload_overrides = {})
    base_payload = {
      "body"         => "<div>channel card html</div>",
      "html"         => true,
      "channel_id"   => channel.id,
      "reply_handle" => "detail-1234",
      "reply_target" => "channel_detail"
    }.merge(payload_overrides)
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload: base_payload
    )
  end

  it "registers for the channel_detail target in :append mode" do
    expect(described_class.target).to eq("channel_detail")
    expect(described_class.mode).to eq(:append)
  end

  it "declares visit, sync and analyze actions" do
    expect(described_class.actions).to eq([ "visit", "sync", "analyze" ])
  end

  it "is NOT internal (appears in help and suggestions)" do
    expect(described_class.internal?).to be false
  end

  # ── visit channel ─────────────────────────────────────────────────────────────

  describe "#call — visit channel (canonical destination)" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "visit channel", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends one system event" do
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq("system")
    end

    it "renders the visiting shimmer" do
      expect(result.events.first[:payload]["body"]).to include("pito-shimmer")
    end

    it "includes the channel's YouTube URL (not Studio)" do
      expect(result.events.first[:payload]["body"]).to include("www.youtube.com/@alpha")
      expect(result.events.first[:payload]["body"]).not_to include("studio.youtube.com")
    end

    it "stamps visit_destination as 'channel'" do
      expect(result.events.first[:payload]["visit_destination"]).to eq("channel")
    end

    it "includes the auto-visit Stimulus controller" do
      expect(result.events.first[:payload]["body"]).to include('data-controller="pito--auto-visit"')
    end
  end

  # ── visit youtube / yt (synonyms) ─────────────────────────────────────────────

  describe "#call — visit youtube (synonym for channel)" do
    let(:source_event) { build_detail_event }

    it "resolves to the YouTube channel URL" do
      result = handler.call(event: source_event, rest: "visit youtube", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["body"]).to include("www.youtube.com/@alpha")
      expect(result.events.first[:payload]["visit_destination"]).to eq("channel")
    end
  end

  describe "#call — visit yt (synonym for channel)" do
    let(:source_event) { build_detail_event }

    it "resolves to the YouTube channel URL" do
      result = handler.call(event: source_event, rest: "visit yt", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["body"]).to include("www.youtube.com/@alpha")
      expect(result.events.first[:payload]["visit_destination"]).to eq("channel")
    end
  end

  # ── visit studio ─────────────────────────────────────────────────────────────

  describe "#call — visit studio" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "visit studio", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "includes the Studio URL (studio.youtube.com)" do
      expect(result.events.first[:payload]["body"]).to include("studio.youtube.com/channel/UCabc")
    end

    it "does NOT include the regular YouTube channel URL" do
      expect(result.events.first[:payload]["body"]).not_to include("www.youtube.com/@alpha")
    end

    it "stamps visit_destination as 'studio'" do
      expect(result.events.first[:payload]["visit_destination"]).to eq("studio")
    end
  end

  # ── bare visit (no destination) ──────────────────────────────────────────────

  describe "#call — bare visit (missing destination)" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "visit", conversation:) }

    it "returns a Result::Error" do
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the needs_destination error key" do
      expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.needs_destination")
    end
  end

  # ── unknown destination word ─────────────────────────────────────────────────

  describe "#call — visit with unknown destination" do
    let(:source_event) { build_detail_event }

    it "returns a needs_destination error for an unrecognised word" do
      result = handler.call(event: source_event, rest: "visit tiktok", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.needs_destination")
    end
  end

  # ── unknown action ─────────────────────────────────────────────────────────

  describe "#call — unknown action" do
    let(:source_event) { build_detail_event }

    it "returns a Result::Error with invalid_action key" do
      result = handler.call(event: source_event, rest: "open", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.invalid_action")
      expect(result.message_args[:action]).to eq("open")
    end
  end

  # ── channel not found ───────────────────────────────────────────────────────

  describe "#call — channel missing from DB" do
    it "returns a channel_not_found error" do
      event = build_detail_event("channel_id" => 0)
      result = handler.call(event: event, rest: "visit channel", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.channel_not_found")
    end
  end

  # ── registry ─────────────────────────────────────────────────────────────────

  describe "registry" do
    it "is registered under 'channel_detail'" do
      expect(Pito::FollowUp::Registry.for("channel_detail")).to eq(described_class)
    end

    it "has mode :append" do
      expect(Pito::FollowUp::Registry.mode_for("channel_detail")).to eq(:append)
    end

    it "reports 'visit' as an available action via Registry" do
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include("visit")
    end
  end
end
