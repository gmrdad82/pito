# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../../support/notification_double"

RSpec.describe Pito::Notifications::Formatter::Templates::YoutubeReauthNeeded do
  def notification(payload)
    NotificationDouble.new(
      event_payload: payload,
      id:            11,
      source_calendar_entry_id: nil,
      severity:      "urgent",
      event_type:    "youtube_reauth_needed",
      fires_at:      Time.current,
      read_at:       nil
    )
  end

  context "with full payload" do
    let(:payload) do
      { "connection_id" => 3, "connection_email" => "owner@example.com" }
    end

    subject { described_class.new(notification(payload)) }

    it "title includes the email" do
      expect(subject.title).to eq("youtube re-auth needed: owner@example.com")
    end

    it "body mentions the email and contains the re-auth link" do
      expect(subject.body).to include("owner@example.com")
      expect(subject.body).to include("[re-authorize](/oauth/youtube/start)")
    end

    it "url is REAUTH_PATH" do
      expect(subject.url).to eq("/oauth/youtube/start")
    end
  end

  context "with missing connection_email" do
    let(:payload) { {} }

    it "title contains placeholder" do
      expect(described_class.new(notification(payload)).title).to include("connection email")
    end

    it "url is still REAUTH_PATH" do
      expect(described_class.new(notification(payload)).url).to eq("/oauth/youtube/start")
    end
  end
end
