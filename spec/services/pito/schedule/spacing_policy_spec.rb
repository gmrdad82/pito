# frozen_string_literal: true

require "rails_helper"

# The scheduling-proximity LAW's math, in one place: 4h spacing + the rolling
# 24h day-cap of 2, published vids counting via published_at, batch siblings
# via extra:, and the grandfathering rule (pre-existing violations never
# block by themselves — the candidate must be a member of any triple it
# rejects). The model/handler/executor specs prove the wiring; this file
# proves the verdicts.
RSpec.describe Pito::Schedule::SpacingPolicy do
  let!(:channel) { create(:channel) }
  let(:video)    { create(:video, channel: channel, publish_at: nil) }

  def verdict(at:, extra: [])
    described_class.call(video: video, at: at, extra: extra)
  end

  describe "spacing (4h air)" do
    it "flags a scheduled neighbor under 4h away, naming it" do
      create(:video, channel: channel, title: "Anchor", publish_at: 10.days.from_now)
      v = verdict(at: 10.days.from_now + 3.hours + 59.minutes)
      expect(v).to include(kind: :spacing, title: "Anchor")
    end

    it "passes at exactly 4h" do
      anchor = create(:video, channel: channel, publish_at: 10.days.from_now)
      expect(verdict(at: anchor.publish_at + 4.hours)).to be_nil
    end

    it "flags a PUBLISHED neighbor via published_at" do
      create(:video, :public, channel: channel, title: "Live One",
             publish_at: nil, published_at: 2.hours.ago)
      expect(verdict(at: Time.current)).to include(kind: :spacing, title: "Live One")
    end

    it "reports the NEAREST offender when several crowd the window" do
      create(:video, channel: channel, title: "Far", publish_at: 10.days.from_now)
      create(:video, channel: channel, title: "Near", publish_at: 10.days.from_now + 2.hours)
      v = verdict(at: 10.days.from_now + 3.hours)
      expect(v[:title]).to eq("Near")
    end
  end

  describe "day cap (max 2 per rolling 24h)" do
    it "rejects a candidate that becomes the third inside one 24h span" do
      base = 10.days.from_now
      create(:video, channel: channel, title: "A", publish_at: base)
      create(:video, channel: channel, title: "B", publish_at: base + 8.hours)
      v = verdict(at: base + 16.hours)
      expect(v[:kind]).to eq(:day_cap)
      expect(v[:titles]).to contain_exactly("A", "B")
    end

    it "GRANDFATHERS a pre-existing triple the candidate does not join" do
      base = 10.days.from_now
      create(:video, channel: channel, publish_at: base)
      create(:video, channel: channel, publish_at: base + 6.hours)
      create(:video, channel: channel, publish_at: base + 12.hours)
      # 40h later: far outside any 24h window containing the triple, and >4h
      # from each — history never blocks a clean new act.
      expect(verdict(at: base + 40.hours)).to be_nil
    end

    it "spans midnight (rolling window, not calendar day)" do
      night = 10.days.from_now.change(hour: 22)
      create(:video, channel: channel, title: "Late", publish_at: night)
      create(:video, channel: channel, title: "Later", publish_at: night + 5.hours)
      v = verdict(at: night + 10.hours)
      expect(v[:kind]).to eq(:day_cap)
    end
  end

  describe "extra: batch siblings" do
    it "judges spacing against staged siblings not yet in the DB" do
      v = verdict(at: 10.days.from_now,
                  extra: [ { time: 10.days.from_now + 2.hours, title: "Sibling" } ])
      expect(v).to include(kind: :spacing, title: "Sibling")
    end

    it "counts siblings toward the day cap" do
      base = 10.days.from_now
      create(:video, channel: channel, title: "In DB", publish_at: base)
      v = verdict(at: base + 16.hours,
                  extra: [ { time: base + 8.hours, title: "Staged" } ])
      expect(v[:kind]).to eq(:day_cap)
      expect(v[:titles]).to contain_exactly("In DB", "Staged")
    end
  end

  describe ".copy_args" do
    it "maps a spacing verdict to the (mass_)schedule_conflict copy" do
      at = Time.zone.local(2026, 7, 23, 11, 0)
      key, args = described_class.copy_args({ kind: :spacing, title: "Other", at: at }, title: "Mine")
      expect(key).to eq("pito.copy.videos.schedule_conflict")
      expect(args[:other]).to eq("Other")

      key, = described_class.copy_args({ kind: :spacing, title: "Other", at: at }, title: "Mine", mass: true)
      expect(key).to eq("pito.copy.videos.mass_schedule_conflict")
    end

    it "maps a day-cap verdict, joining the window pair" do
      key, args = described_class.copy_args(
        { kind: :day_cap, titles: %w[A B], at: Time.current }, title: "Mine"
      )
      expect(key).to eq("pito.copy.videos.schedule_day_cap")
      expect(args[:others]).to eq("A and B")
    end
  end
end
