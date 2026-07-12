# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::RelativeWhen do
  # A fixed reference so every tier is deterministic. Local zone is what the
  # formatter renders in; build `now` in it.
  let(:now) { Time.zone.local(2026, 3, 1, 10, 0, 0) } # Sun 1 Mar 2026, 10:00

  def when_for(time)
    described_class.call(time, now: now)
  end

  describe "sub-hour → minutes" do
    it "renders whole minutes" do
      expect(when_for(now + 45.minutes)).to eq("in 45 minutes")
    end

    it "renders the singular minute" do
      expect(when_for(now + 60.seconds)).to eq("in a minute")
    end

    it "renders 'any moment now' under a minute" do
      expect(when_for(now + 20.seconds)).to eq("any moment now")
    end
  end

  describe "same day → hours" do
    it "renders whole hours" do
      expect(when_for(now + 3.hours)).to eq("in 3 hours")
    end

    it "renders the singular hour" do
      expect(when_for(now + 1.hour)).to eq("in an hour")
    end
  end

  describe "tomorrow → 'tomorrow at <clock>'" do
    it "uses 'noon' for 12:00" do
      expect(when_for(Time.zone.local(2026, 3, 2, 12, 0))).to eq("tomorrow at noon")
    end

    it "uses 'midnight' for 00:00" do
      expect(when_for(Time.zone.local(2026, 3, 2, 0, 0))).to eq("tomorrow at midnight")
    end

    it "uses a 24h clock otherwise" do
      expect(when_for(Time.zone.local(2026, 3, 2, 9, 5))).to eq("tomorrow at 09:05")
    end
  end

  describe "2–6 days → 'in N days'" do
    it "renders the day count" do
      expect(when_for(now + 2.days)).to eq("in 2 days")
    end

    it "still relative on day 6" do
      expect(when_for(now + 6.days)).to eq("in 6 days")
    end
  end

  describe "≥7 days → absolute 'on <ordinal> of <Month>'" do
    it "renders the ordinal day + month" do
      expect(when_for(Time.zone.local(2026, 3, 21, 9, 0))).to eq("on 21st of March")
    end

    it "renders 1st correctly" do
      expect(when_for(Time.zone.local(2026, 4, 1, 9, 0))).to eq("on 1st of April")
    end

    it "appends the year when it is not the current year" do
      expect(when_for(Time.zone.local(2027, 1, 5, 9, 0))).to eq("on 5th of January 2027")
    end
  end

  describe "edge cases" do
    it "returns the fallback for a blank time" do
      expect(described_class.call(nil, now: now)).to eq("—")
    end

    it "returns the fallback for a non-future time" do
      expect(described_class.call(now - 1.hour, now: now)).to eq("—")
    end
  end
end
