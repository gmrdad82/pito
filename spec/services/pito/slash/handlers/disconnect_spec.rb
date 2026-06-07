# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Disconnect, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(raw:, authenticated: true)
    invocation = Pito::Slash::Invocation.new(
      verb:   :disconnect,
      args:   [],
      kwargs: {},
      raw:    raw
    )
    described_class.new(invocation:, conversation:, authenticated:)
  end

  describe "#call — missing target" do
    it "returns an error event" do
      result = build_handler(raw: "/disconnect").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:kind]).to eq("error")
      expect(result.events.first[:payload]["text"]).to include("Usage")
    end
  end

  describe "#call — @handle not found" do
    it "returns an error event" do
      result = build_handler(raw: "/disconnect @nobody").call
      expect(result.events.first[:kind]).to eq("error")
      expect(result.events.first[:payload]["text"]).to include("@nobody")
    end
  end

  describe "#call — numeric id not found" do
    it "returns an error event" do
      result = build_handler(raw: "/disconnect 99999").call
      expect(result.events.first[:kind]).to eq("error")
      expect(result.events.first[:payload]["text"]).to include("99999")
    end
  end

  describe "#call — case-sensitive @handle matching" do
    let!(:channel) { create(:channel, handle: "@GamingChannel") }

    it "matches the exact case" do
      result = build_handler(raw: "/disconnect @GamingChannel").call
      expect(result.events.first[:kind]).to eq("confirmation")
    end

    it "does not match a differently-cased handle" do
      result = build_handler(raw: "/disconnect @gamingchannel").call
      expect(result.events.first[:kind]).to eq("error")
    end
  end

  describe "#call — @handle found (partial match)" do
    let!(:channel) { create(:channel, handle: "@gamingchannel") }

    it "returns a confirmation event" do
      result = build_handler(raw: "/disconnect @gaming").call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:kind]).to eq("confirmation")
    end

    it "includes command: disconnect in the payload" do
      result = build_handler(raw: "/disconnect @gaming").call
      expect(result.events.first[:payload]["command"]).to eq("disconnect")
    end

    it "includes the channel_id in the payload" do
      result = build_handler(raw: "/disconnect @gaming").call
      expect(result.events.first[:payload]["channel_id"]).to eq(channel.id)
    end

    it "includes a reply_handle (follow-up engine stamp)" do
      result = build_handler(raw: "/disconnect @gaming").call
      payload = result.events.first[:payload]
      handle = payload[:reply_handle] || payload["reply_handle"]
      expect(handle).to match(/\A[a-z]+-\d{4}\z/)
    end

    it "includes reply_target: 'confirmation'" do
      result = build_handler(raw: "/disconnect @gaming").call
      payload = result.events.first[:payload]
      target = payload[:reply_target] || payload["reply_target"]
      expect(target).to eq("confirmation")
    end

    it "includes a body with the cyan-wrapped handle" do
      result = build_handler(raw: "/disconnect @gaming").call
      body = result.events.first[:payload]["body"]
      expect(body).to include("<span class=\"text-cyan\">@gamingchannel</span>")
      expect(result.events.first[:payload]["html"]).to be(true)
    end

    it "includes expand_detail with channel stats (subscribers, views) first" do
      result = build_handler(raw: "/disconnect @gaming").call
      detail = result.events.first[:payload]["expand_detail"]
      expect(detail).to be_an(Array)
      expect(detail).not_to be_empty

      # First items are channel stats in KV format
      subscribers_row = detail[0]
      expect(subscribers_row).to be_a(Hash)
      expect(subscribers_row[:key]).to eq("Subscribers")
      expect(subscribers_row[:value]).to be_present

      views_row = detail[1]
      expect(views_row).to be_a(Hash)
      expect(views_row[:key]).to eq("Views")
      expect(views_row[:value]).to be_present

      # No watched_hours — not available in YouTube API
      keys = detail.select { |item| item.is_a?(Hash) }.map { |h| h[:key] }
      expect(keys).not_to include("Watched Hours")
    end

    it "includes video breakdown after the spacer" do
      result = build_handler(raw: "/disconnect @gaming").call
      detail = result.events.first[:payload]["expand_detail"]
      # Find the spacer
      spacer_idx = detail.index { |item| item == "" }
      expect(spacer_idx).to be_present

      # After spacer: video stats
      video_rows = detail[(spacer_idx + 1)..]
      expect(video_rows).not_to be_empty
      expect(video_rows.first).to be_a(Hash)
      expect(video_rows.first[:key]).to eq("Videos")
      expect(video_rows.first[:value]).to eq("0")  # just the number, no label
    end
  end

  describe "#call — numeric id found" do
    let!(:channel) { create(:channel, handle: "@somechannel") }

    it "resolves the channel by local id" do
      result = build_handler(raw: "/disconnect #{channel.id}").call
      expect(result.events.first[:kind]).to eq("confirmation")
      expect(result.events.first[:payload]["channel_id"]).to eq(channel.id)
    end
  end

  describe "#call — video count breakdown in expand_detail" do
    let!(:channel) { create(:channel, :with_videos, handle: "@vidchan") }

    it "includes total video count in the video section" do
      result = build_handler(raw: "/disconnect @vidchan").call
      detail = result.events.first[:payload]["expand_detail"]
      spacer_idx = detail.index { |item| item == "" }
      video_rows = detail[(spacer_idx + 1)..]
      total_row = video_rows.find { |r| r.is_a?(Hash) && r[:key] == "Videos" }
      expect(total_row).to be_present
      expect(total_row[:value]).to include("3")
    end
  end
end
