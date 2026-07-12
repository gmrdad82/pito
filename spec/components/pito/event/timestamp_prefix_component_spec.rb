# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::TimestampPrefixComponent do
  it "renders today's time as bare 24-hour HH:MM (dim) with a trailing space and NO · separator" do
    ts = Time.current.change(hour: 19, min: 58)
    node = render_inline(described_class.new(timestamp: ts))
    expect(node.css("span.pito-timestamp-prefix")).not_to be_empty
    expect(node.css("span.pito-timestamp-prefix").text).to eq("19:58 ")
    expect(node.to_html).not_to include("·")
  end

  it "zero-pads single-digit hours and drops AM/PM (09:05)" do
    ts = Time.current.change(hour: 9, min: 5)
    html = render_inline(described_class.new(timestamp: ts)).to_html
    expect(html).to include("09:05")
    expect(html).not_to include("AM")
    expect(html).not_to include("PM")
  end

  it "prefixes the day (6 Jul) for a same-year message from another day" do
    ts = 5.days.ago.change(hour: 11, min: 4)
    skip "year boundary within 5 days" if ts.year != Time.zone.today.year

    node = render_inline(described_class.new(timestamp: ts))
    expect(node.css("span.pito-timestamp-prefix").text).to eq("#{ts.strftime('%-d %b')} 11:04 ")
  end

  it "carries the short year (1 Jun '25) once the year differs — the badge/tick month shape" do
    ts = Time.zone.parse("2025-06-01 19:58:00")
    node = render_inline(described_class.new(timestamp: ts))
    expect(node.css("span.pito-timestamp-prefix").text).to eq("1 Jun '25 19:58 ")
  end

  it "renders nothing when timestamp is nil" do
    node = render_inline(described_class.new(timestamp: nil))
    expect(node.to_html.strip).to eq("")
  end

  it "renders a UTC-stored timestamp in the configured Time.zone (local wall clock and local DAY)" do
    original = Time.zone
    Time.zone = "Europe/Madrid" # UTC+2 in June (DST)
    utc = Time.utc(Time.zone.today.year, 6, 16, 12, 0, 0)
    html = render_inline(described_class.new(timestamp: utc)).to_html
    expect(html).to include("16 Jun 14:00") unless Time.zone.today == Date.new(Time.zone.today.year, 6, 16)
  ensure
    Time.zone = original
  end
end
