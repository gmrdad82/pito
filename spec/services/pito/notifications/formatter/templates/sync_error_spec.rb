# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../../support/notification_double"

RSpec.describe Pito::Notifications::Formatter::Templates::SyncError do
  def notification(payload, id: 42)
    NotificationDouble.new(
      event_payload: payload,
      id:            id,
      source_calendar_entry_id: nil,
      severity:      "urgent",
      event_type:    "sync_error",
      fires_at:      Time.current,
      read_at:       nil
    )
  end

  context "with full payload" do
    let(:payload) do
      {
        "job_class"     => "SyncVideosJob",
        "error_class"   => "Net::ReadTimeout",
        "error_message" => "read timed out after 10 seconds"
      }
    end

    subject { described_class.new(notification(payload, id: 7)) }

    it "title is 'sync error: <job_class>'" do
      expect(subject.title).to eq("sync error: SyncVideosJob")
    end

    it "body is '<error_class>: <error_message>'" do
      expect(subject.body).to eq("Net::ReadTimeout: read timed out after 10 seconds")
    end

    it "url is /notifications/<id>" do
      expect(subject.url).to eq("/notifications/7")
    end
  end

  context "with empty payload" do
    let(:payload) { {} }

    it "title contains placeholder for job class" do
      expect(described_class.new(notification(payload)).title).to include("job class")
    end

    it "body contains placeholders for both error fields" do
      body = described_class.new(notification(payload)).body
      expect(body).to include("error class")
      expect(body).to include("error message")
    end
  end

  context "when notification id is blank (nil)" do
    it "url is nil" do
      n = NotificationDouble.new(
        event_payload: { "job_class" => "X" },
        id: nil,
        source_calendar_entry_id: nil,
        severity: "urgent",
        event_type: "sync_error",
        fires_at: Time.current,
        read_at: nil
      )
      expect(described_class.new(n).url).to be_nil
    end
  end
end
