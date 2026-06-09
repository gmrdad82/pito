# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::ChannelList do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:channel) do
    create(:channel,
           title:              "Alpha Cast",
           handle:             "@alpha",
           youtube_channel_id: "UCabc")
  end

  it "registers for the channel_list target in :append mode" do
    expect(described_class.target).to eq("channel_list")
    expect(described_class.mode).to eq(:append)
  end

  it "declares the visit and reindex actions" do
    expect(described_class.actions).to eq([ "visit", "reindex" ])
  end

  describe "visit by @handle" do
    subject(:result) do
      handler.call(event: nil, rest: "visit @alpha", conversation:)
    end

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends one system event" do
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq("system")
    end

    it "sets html: true on the payload" do
      expect(result.events.first[:payload]["html"]).to be(true)
    end

    it "includes the pito-shimmer class in the body" do
      expect(result.events.first[:payload]["body"]).to include("pito-shimmer")
    end

    it "includes a youtube.com link in the body" do
      expect(result.events.first[:payload]["body"]).to include("https://www.youtube.com/@alpha")
    end

    it "includes target=_blank on the link" do
      expect(result.events.first[:payload]["body"]).to include('target="_blank"')
    end

    it "includes the pito--auto-visit controller data attribute" do
      expect(result.events.first[:payload]["body"]).to include('data-controller="pito--auto-visit"')
    end

    it "the hidden anchor id matches the link-id-value" do
      body = result.events.first[:payload]["body"]
      # Extract link-id-value
      link_id = body.match(/data-pito--auto-visit-link-id-value="([^"]+)"/)[1]
      expect(body).to include(%(<a id="#{link_id}"))
    end
  end

  describe "visit by numeric id" do
    it "resolves the channel by id and returns Append" do
      result = handler.call(event: nil, rest: "visit #{channel.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["body"]).to include("https://www.youtube.com/@alpha")
    end
  end

  describe "visit by handle without @ prefix" do
    it "resolves the channel when @ is omitted" do
      result = handler.call(event: nil, rest: "visit alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end
  end

  describe "invalid action" do
    it "returns Result::Error for an unknown action" do
      result = handler.call(event: nil, rest: "open @alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_list.errors.invalid_action")
    end
  end

  describe "not found" do
    it "returns Result::Error when the channel is not found by handle" do
      result = handler.call(event: nil, rest: "visit @unknown_channel_xyz", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_list.errors.not_found")
      expect(result.message_args[:ref]).to include("unknown_channel_xyz")
    end

    it "returns Result::Error when the channel is not found by id" do
      result = handler.call(event: nil, rest: "visit 99999", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_list.errors.not_found")
    end
  end

  describe "channel with no handle (youtube_channel_id fallback)" do
    let!(:no_handle_channel) do
      create(:channel, title: "No Handle Chan", handle: nil, youtube_channel_id: "UCnohandle")
    end

    it "builds a /channel/ URL when handle is blank" do
      result = handler.call(event: nil, rest: "visit #{no_handle_channel.id}", conversation:)
      expect(result.events.first[:payload]["body"]).to include("https://www.youtube.com/channel/UCnohandle")
    end
  end

  # ── reindex @handle ───────────────────────────────────────────────────────────

  describe "reindex @handle" do
    subject(:result) do
      handler.call(event: nil, rest: "reindex @alpha", conversation:)
    end

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends one confirmation event" do
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq("confirmation")
    end

    it "emits a channel_reindex confirmation" do
      expect(result.events.first[:payload]["command"]).to eq("channel_reindex")
    end

    it "carries channel_id and channel_handle" do
      payload = result.events.first[:payload]
      expect(payload["channel_id"]).to eq(channel.id)
      expect(payload["channel_handle"]).to eq("@alpha")
    end

    it "stamps the confirmation as followupable" do
      expect(result.events.first[:payload]["reply_target"]).to eq("confirmation")
    end
  end

  describe "reindex by handle without @ prefix" do
    it "resolves the channel when @ is omitted" do
      result = handler.call(event: nil, rest: "reindex alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["command"]).to eq("channel_reindex")
    end
  end

  describe "reindex — unknown channel" do
    it "returns Result::Error when the channel is not found" do
      result = handler.call(event: nil, rest: "reindex @nonexistent_xyz", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_list.errors.not_found")
      expect(result.message_args[:ref]).to include("nonexistent_xyz")
    end
  end
end
