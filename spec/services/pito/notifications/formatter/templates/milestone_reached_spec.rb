# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../../support/notification_double"

RSpec.describe Pito::Notifications::Formatter::Templates::MilestoneReached do
  def notification(payload, cal_entry_id: nil)
    NotificationDouble.new(
      event_payload:            payload,
      id:                       10,
      source_calendar_entry_id: cal_entry_id,
      severity:                 "success",
      event_type:               "milestone_reached",
      fires_at:                 Time.current,
      read_at:                  nil
    )
  end

  context "with full payload + scope_label" do
    let(:payload) do
      {
        "rule_name"             => "100K views",
        "metric"                => "views",
        "threshold"             => 100_000,
        "metric_value_at_fire"  => 100_042,
        "scope_type"            => "channel",
        "scope_label"           => "Pito Demo"
      }
    end

    subject { described_class.new(notification(payload, cal_entry_id: 5)) }

    it "title is 'milestone: <rule_name>'" do
      expect(subject.title).to eq("milestone: 100K views")
    end

    it "body mentions metric, threshold, value, and scope_label" do
      expect(subject.body).to eq("views crossed 100000 at 100042 on Pito Demo.")
    end

    it "url points at /calendar/entries/<source_calendar_entry_id>" do
      expect(subject.url).to eq("/calendar/entries/5")
    end
  end

  context "with scope_type 'install' and no scope_label" do
    let(:payload) do
      {
        "rule_name"            => "First game",
        "metric"               => "games",
        "threshold"            => 1,
        "metric_value_at_fire" => 1,
        "scope_type"           => "install"
      }
    end

    it "body mentions 'this install'" do
      expect(described_class.new(notification(payload)).body).to include("this install")
    end
  end

  context "with missing source_calendar_entry_id" do
    let(:payload) { { "rule_name" => "50K" } }

    it "url is nil" do
      expect(described_class.new(notification(payload)).url).to be_nil
    end
  end

  context "with empty payload" do
    let(:payload) { {} }

    it "title contains placeholder" do
      expect(described_class.new(notification(payload)).title).to include("rule name")
    end

    it "body uses placeholders for all missing keys" do
      body = described_class.new(notification(payload)).body
      expect(body).to include("metric")
      expect(body).to include("threshold")
    end
  end
end
