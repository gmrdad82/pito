# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../../support/notification_double"

RSpec.describe Pito::Notifications::Formatter::Templates::VideoDiffDetected do
  def notification(payload)
    NotificationDouble.new(
      event_payload: payload,
      id:            8,
      source_calendar_entry_id: nil,
      severity:      "warn",
      event_type:    "video_diff_detected",
      fires_at:      Time.current,
      read_at:       nil
    )
  end

  context "with full payload" do
    let(:payload) do
      {
        "video_id"    => 20,
        "video_slug"  => "demo-reel-v2",
        "video_title" => "Demo Reel V2",
        "diff_id"     => 99,
        "fields"      => %w[title description]
      }
    end

    subject { described_class.new(notification(payload)) }

    it "title reports the field count" do
      expect(subject.title).to eq("youtube diverged on 2 fields")
    end

    it "uses singular 'field' for exactly one field" do
      n = notification(payload.merge("fields" => [ "title" ]))
      expect(described_class.new(n).title).to eq("youtube diverged on 1 field")
    end

    it "body names the video and lists the fields" do
      expect(subject.body).to include("Demo Reel V2")
      expect(subject.body).to include("title, description")
    end

    it "url is /videos/<video_slug>/diff" do
      expect(subject.url).to eq("/videos/demo-reel-v2/diff")
    end
  end

  context "with empty fields array" do
    let(:payload) { { "video_slug" => "s", "video_title" => "T", "fields" => [] } }

    it "body falls back to '(no fields)'" do
      expect(described_class.new(notification(payload)).body).to include("(no fields)")
    end
  end

  context "without video_slug" do
    let(:payload) { { "video_title" => "T", "fields" => [ "title" ] } }

    it "url is nil" do
      expect(described_class.new(notification(payload)).url).to be_nil
    end
  end

  context "with empty payload" do
    let(:payload) { {} }

    it "title still contains a count (0 fields)" do
      expect(described_class.new(notification(payload)).title).to eq("youtube diverged on 0 fields")
    end
  end
end
