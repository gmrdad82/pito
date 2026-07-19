# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::SyncStamp do
  include ActiveSupport::Testing::TimeHelpers

  it "collapses to bare '%H:%M' when the time is today (the date drops entirely)" do
    travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
      time = Time.zone.local(2026, 7, 19, 14, 30)
      expect(described_class.call(time)).to eq("14:30")
    end
  end

  it "renders '%-d %b %H:%M' for a same-year, non-today time" do
    travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
      time = Time.zone.local(2026, 6, 2, 14, 30)
      expect(described_class.call(time)).to eq("2 Jun 14:30")
    end
  end

  it "renders '%-d %b 'YY %H:%M' for a past year" do
    travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
      time = Time.zone.local(2025, 6, 2, 14, 30)
      expect(described_class.call(time)).to eq("2 Jun '25 14:30")
    end
  end

  it "renders '%-d %b 'YY %H:%M' for a future year" do
    travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
      time = Time.zone.local(2027, 1, 5, 8, 0)
      expect(described_class.call(time)).to eq("5 Jan '27 08:00")
    end
  end

  it "converts a UTC time into the app zone before formatting" do
    travel_to(Time.zone.local(2026, 1, 1, 9, 0)) do
      time = Time.utc(2026, 1, 5, 23, 45)
      expect(described_class.call(time)).to eq(time.in_time_zone.strftime("%-d %b %H:%M"))
    end
  end

  it "returns the em-dash fallback for nil" do
    expect(described_class.call(nil)).to eq("—")
  end

  it "returns a custom fallback when given" do
    expect(described_class.call(nil, fallback: "never synced")).to eq("never synced")
  end

  it "delegates to Pito::Formatter::HouseDate.stamp" do
    travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
      time = Time.zone.local(2026, 6, 2, 14, 30)
      expect(described_class.call(time)).to eq(Pito::Formatter::HouseDate.stamp(time))
    end
  end
end
