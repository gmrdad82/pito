# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../../support/notification_double"

RSpec.describe Pito::Notifications::Formatter::Templates::CalendarEntryFiring do
  def notification(payload, cal_entry_id: nil)
    NotificationDouble.new(
      event_payload:            payload,
      id:                       9,
      source_calendar_entry_id: cal_entry_id,
      severity:                 "info",
      event_type:               "calendar_entry_firing",
      fires_at:                 Time.current,
      read_at:                  nil
    )
  end

  context "with full payload" do
    let(:payload) do
      {
        "entry_id"    => 33,
        "entry_type"  => "milestone_manual",
        "title"       => "Product Hunt Launch",
        "description" => "Our PH launch day — post at 12:01 AM PST.",
        "starts_at"   => "2026-07-01T07:01:00Z"
      }
    end

    subject { described_class.new(notification(payload, cal_entry_id: 33)) }

    it "title is the calendar entry title" do
      expect(subject.title).to eq("Product Hunt Launch")
    end

    it "body is the description" do
      expect(subject.body).to eq("Our PH launch day — post at 12:01 AM PST.")
    end

    it "url uses entry_id from payload first" do
      expect(subject.url).to eq("/calendar/entries/33")
    end
  end

  context "when entry_id is absent in payload but source_calendar_entry_id set" do
    let(:payload) { { "title" => "Backup test" } }

    it "url falls back to source_calendar_entry_id" do
      expect(described_class.new(notification(payload, cal_entry_id: 77)).url)
        .to eq("/calendar/entries/77")
    end
  end

  context "with blank description" do
    let(:payload) { { "entry_id" => 1, "title" => "T", "description" => "" } }

    it "body returns the EMPTY_BODY_FALLBACK string" do
      expect(described_class.new(notification(payload)).body)
        .to eq(described_class::EMPTY_BODY_FALLBACK)
    end
  end

  context "with nil description" do
    let(:payload) { { "entry_id" => 1, "title" => "T" } }

    it "body returns the EMPTY_BODY_FALLBACK string" do
      expect(described_class.new(notification(payload)).body)
        .to eq(described_class::EMPTY_BODY_FALLBACK)
    end
  end

  context "with empty payload and no source_calendar_entry_id" do
    let(:payload) { {} }

    it "title contains placeholder" do
      expect(described_class.new(notification(payload)).title).to include("calendar entry title")
    end

    it "url is nil" do
      expect(described_class.new(notification(payload)).url).to be_nil
    end
  end
end
