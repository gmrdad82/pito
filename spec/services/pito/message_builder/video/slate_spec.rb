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

  describe "week / rest split" do
    it "emits only the :system week message for period 7d" do
      scheduled(2.days.from_now)
      events = call(period: "7d")
      expect(events.size).to eq(1)
      expect(events.first[:kind]).to eq(:system)
      expect(events.first[:payload]["table_rows"].size).to eq(1)
    end

    it "adds an :enhanced rest message for a longer period when the rest window has vids" do
      scheduled(2.days.from_now)   # this week
      scheduled(14.days.from_now)  # the rest
      events = call(period: "28d")
      expect(events.map { |e| e[:kind] }).to eq(%i[system enhanced])
      expect(events[0][:payload]["table_rows"].size).to eq(1)
      expect(events[1][:payload]["table_rows"].size).to eq(1)
    end

    it "omits the :enhanced message when period > 7d but the rest window is empty" do
      scheduled(2.days.from_now)
      events = call(period: "28d")
      expect(events.size).to eq(1)
      expect(events.first[:kind]).to eq(:system)
    end

    it "treats `lifetime` as unbounded (still splits week vs rest)" do
      scheduled(3.days.from_now)
      scheduled(200.days.from_now)
      events = call(period: "lifetime")
      expect(events.map { |e| e[:kind] }).to eq(%i[system enhanced])
    end

    it "collapses an unrecognised/discrete period to a week-only window (no enhanced)" do
      scheduled(3.days.from_now)
      scheduled(14.days.from_now)
      events = call(period: "May")
      expect(events.size).to eq(1)
      expect(events.first[:kind]).to eq(:system)
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

  describe "rendering" do
    it "renders channel and game columns (no Scheduled column)" do
      scheduled(Time.zone.local(2026, 6, 24, 14, 30))
      payload = call(period: "7d").first[:payload]
      heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(heading_texts).to include("Channel")
      expect(heading_texts).not_to include("Scheduled")
    end

    it "renders a witty empty message (no table) when nothing is scheduled" do
      events = call(period: "7d")
      expect(events.size).to eq(1)
      expect(events.first[:payload]["text"]).to be_present
      expect(events.first[:payload]["table_rows"]).to be_nil
    end
  end
end
