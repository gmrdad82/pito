# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::SyncStamp do
  it "renders DD-MM-YYYY HH:MM in the local zone" do
    time = Time.zone.local(2026, 7, 2, 14, 30)
    expect(described_class.call(time)).to eq("02-07-2026 14:30")
  end

  it "converts a UTC time into the app zone" do
    time = Time.utc(2026, 1, 5, 23, 45)
    expect(described_class.call(time)).to eq(time.in_time_zone.strftime("%d-%m-%Y %H:%M"))
  end

  it "returns the em-dash fallback for nil" do
    expect(described_class.call(nil)).to eq("—")
  end

  it "returns a custom fallback when given" do
    expect(described_class.call(nil, fallback: "never synced")).to eq("never synced")
  end

  it "zero-pads day, month, hour and minute" do
    time = Time.zone.local(2026, 3, 4, 5, 6)
    expect(described_class.call(time)).to eq("04-03-2026 05:06")
  end
end
