# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../../support/notification_double"

RSpec.describe Pito::Notifications::Formatter::Templates::VideoPublished do
  def notification(payload)
    NotificationDouble.new(
      event_payload: payload,
      id:            3,
      source_calendar_entry_id: nil,
      severity:      "success",
      event_type:    "video_published",
      fires_at:      Time.current,
      read_at:       nil
    )
  end

  context "with full payload including watch_url" do
    let(:payload) do
      {
        "video_id"      => 55,
        "video_title"   => "Pito Demo Reel",
        "channel_title" => "Pito HQ",
        "channel_id"    => 2,
        "published_at"  => "2026-06-04T12:00:00Z",
        "watch_url"     => "https://youtu.be/abc123"
      }
    end

    subject { described_class.new(notification(payload)) }

    it "title is 'published: <video_title>'" do
      expect(subject.title).to eq("published: Pito Demo Reel")
    end

    it "body includes channel, title, and watch link" do
      expect(subject.body).to include("Pito HQ")
      expect(subject.body).to include("Pito Demo Reel")
      expect(subject.body).to include("[watch on youtube](https://youtu.be/abc123)")
    end

    it "url is /videos/<video_id>" do
      expect(subject.url).to eq("/videos/55")
    end
  end

  context "without watch_url" do
    let(:payload) { { "video_title" => "My Vid", "channel_title" => "Chan", "video_id" => 6 } }

    it "body omits the watch link" do
      body = described_class.new(notification(payload)).body
      expect(body).not_to include("watch on youtube")
      expect(body).to eq("Chan just published My Vid.")
    end
  end

  context "with empty payload" do
    let(:payload) { {} }

    it "title contains placeholder" do
      expect(described_class.new(notification(payload)).title).to include("video title")
    end

    it "url is nil" do
      expect(described_class.new(notification(payload)).url).to be_nil
    end
  end
end
