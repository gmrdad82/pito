# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::Slate do
  include ActiveSupport::Testing::TimeHelpers

  let(:conversation) { Conversation.singleton }
  let(:channel)      { create(:channel, handle: "@chan") }

  # Tuesday 2026-06-23 12:00 UTC — fixed so window math is deterministic.
  now = Time.find_zone("UTC").local(2026, 6, 23, 12, 0)
  around { |ex| Time.use_zone("UTC") { travel_to(now) { ex.run } } }

  def scheduled(publish_at, on: channel)
    create(:video, channel: on, privacy_status: :private, publish_at: publish_at)
  end

  def call(period:, exclude_id: nil, channel_scope: "@all")
    described_class.call(exclude_id:, channel_scope:, period:, conversation:)
  end

  describe "combined list (no week/rest split)" do
    it "emits a single :system list for period 7d" do
      scheduled(2.days.from_now)
      events = call(period: "7d")
      expect(events.size).to eq(1)
      expect(events.first[:kind]).to eq(:system)
      expect(events.first[:payload]["table_rows"].size).to eq(1)
    end

    it "combines the whole period into ONE list (28d) — near and far together" do
      scheduled(2.days.from_now)
      scheduled(14.days.from_now)
      events = call(period: "28d")
      expect(events.map { |e| e[:kind] }).to eq(%i[system])
      expect(events.first[:payload]["table_rows"].size).to eq(2)
    end

    it "spans `lifetime` (unbounded) in one list" do
      scheduled(3.days.from_now)
      scheduled(200.days.from_now)
      events = call(period: "lifetime")
      expect(events.size).to eq(1)
      expect(events.first[:payload]["table_rows"].size).to eq(2)
    end

    it "bounds by the period window (unrecognised/discrete → week-only)" do
      scheduled(3.days.from_now)   # inside the week window
      scheduled(14.days.from_now)  # outside it
      events = call(period: "May")
      expect(events.size).to eq(1)
      expect(events.first[:payload]["table_rows"].size).to eq(1)
    end
  end

  describe "filtering" do
    it "excludes the reference vid" do
      keep = scheduled(2.days.from_now)
      drop = scheduled(3.days.from_now)
      expect(call(period: "7d", exclude_id: drop.id).first[:payload]["video_ids"]).to eq([ keep.id ])
    end

    it "obeys the channel scope" do
      mine  = scheduled(2.days.from_now, on: channel)
      scheduled(2.days.from_now, on: create(:channel, handle: "@other"))
      expect(call(period: "7d", channel_scope: "@chan").first[:payload]["video_ids"]).to eq([ mine.id ])
    end

    it "counts only scheduled vids (private + future publish_at)" do
      create(:video, channel:, privacy_status: :public)
      create(:video, channel:, privacy_status: :private, publish_at: 1.day.ago)
      events = call(period: "7d")
      expect(events.first[:payload]["text"]).to be_present  # empty → Text payload
      expect(events.first[:payload]["table_rows"]).to be_nil
    end

    it "orders by publish_at ascending" do
      late  = scheduled(5.days.from_now)
      early = scheduled(1.day.from_now)
      expect(call(period: "7d").first[:payload]["video_ids"]).to eq([ early.id, late.id ])
    end
  end

  describe "only @handles filter" do
    let!(:ch_a) { create(:channel, handle: "@a") }
    let!(:ch_b) { create(:channel, handle: "@b") }
    let!(:ch_c) { create(:channel, handle: "@c") }

    def slate_ids(only_handles:)
      described_class.call(
        exclude_id: nil, channel_scope: "@all", period: "7d", conversation:, only_handles:
      ).first[:payload]["video_ids"]
    end

    it "scopes to the UNION of the named channels, overriding shift+tab" do
      va = scheduled(2.days.from_now, on: ch_a)
      vb = scheduled(3.days.from_now, on: ch_b)
      scheduled(2.days.from_now, on: ch_c) # not named → excluded
      expect(slate_ids(only_handles: %w[@a @b])).to match_array([ va.id, vb.id ])
    end

    it "ignores unknown handles (match nothing)" do
      va = scheduled(2.days.from_now, on: ch_a)
      expect(slate_ids(only_handles: %w[@a @nope])).to eq([ va.id ])
    end

    it "is tolerant of missing @ and case" do
      va = scheduled(2.days.from_now, on: ch_a)
      expect(slate_ids(only_handles: %w[A])).to eq([ va.id ])
    end
  end

  describe "rendering" do
    it "renders the Channel + Go-live columns (Game swapped out)" do
      scheduled(Time.zone.local(2026, 6, 24, 14, 30))
      payload = call(period: "7d").first[:payload]
      heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(heading_texts).to include("Channel").and include("Go live")
      expect(heading_texts).not_to include("Game")
    end

    it "renders the go-live time in human form" do
      scheduled(now + 3.hours)
      payload    = call(period: "7d").first[:payload]
      cells_text = payload["table_rows"].first[:cells].map { |c| c[:text] }.join(" ")
      expect(cells_text).to include("in 3 hours")
    end

    it "renders a witty empty message (no table) when nothing is scheduled" do
      events = call(period: "7d")
      expect(events.size).to eq(1)
      expect(events.first[:payload]["text"]).to be_present
      expect(events.first[:payload]["table_rows"]).to be_nil
    end
  end
end
